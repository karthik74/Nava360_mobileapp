import 'dart:async';
import 'dart:convert';

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_client.dart';
import 'credit_sms_models.dart';
import 'credit_sms_parser.dart';
import 'credit_sms_repository.dart';

/// Durable, de-duplicated outbox for parsed credits. Persists to encrypted
/// storage so detections survive app restarts and offline periods, then drains
/// to the backend when connectivity returns.
class CreditSmsOutbox {
  static const _kQueue = 'credit_sms.outbox';
  static const _kSeen = 'credit_sms.seen_hashes';
  static const _opts = AndroidOptions(encryptedSharedPreferences: true);
  static const _storage = FlutterSecureStorage(aOptions: _opts);

  /// Cap on remembered hashes so the de-dupe set can't grow unbounded.
  static const _maxSeen = 500;

  Future<List<ParsedCreditSms>> _readQueue() async {
    final raw = await _storage.read(key: _kQueue);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ParsedCreditSms.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeQueue(List<ParsedCreditSms> q) =>
      _storage.write(key: _kQueue, value: jsonEncode(q.map((e) => e.toJson()).toList()));

  Future<List<String>> _readSeen() async {
    final raw = await _storage.read(key: _kSeen);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List<dynamic>).cast<String>();
  }

  Future<void> _writeSeen(List<String> seen) async {
    final trimmed = seen.length > _maxSeen
        ? seen.sublist(seen.length - _maxSeen)
        : seen;
    await _storage.write(key: _kSeen, value: jsonEncode(trimmed));
  }

  /// Add a parsed credit unless its hash was already queued or uploaded.
  Future<bool> enqueue(ParsedCreditSms parsed) async {
    final seen = await _readSeen();
    if (seen.contains(parsed.rawHash)) return false;
    final q = await _readQueue();
    if (q.any((e) => e.rawHash == parsed.rawHash)) return false;
    q.add(parsed);
    await _writeQueue(q);
    return true;
  }

  Future<int> pendingCount() async => (await _readQueue()).length;

  /// Try to upload every queued item. Successful (or server-side duplicate)
  /// items are removed and their hash remembered; network failures are kept.
  Future<void> flush(CreditSmsRepository repo) async {
    final q = await _readQueue();
    if (q.isEmpty) return;
    final seen = await _readSeen();
    final remaining = <ParsedCreditSms>[];
    var uploaded = 0;
    var dropped = 0;
    var kept = 0;

    for (final item in q) {
      try {
        await repo.upload(item);
        seen.add(item.rawHash);
        uploaded++;
      } on ApiException catch (e) {
        // 4xx (e.g. duplicate, consent off) is terminal for this item — drop it,
        // don't retry forever. Only keep on network/5xx so we retry later.
        final code = e.statusCode ?? 0;
        if (code >= 400 && code < 500) {
          seen.add(item.rawHash);
          dropped++;
          debugPrint('[credit-sms] upload dropped (HTTP $code): ${e.message}');
        } else {
          remaining.add(item);
          kept++;
          debugPrint('[credit-sms] upload retry later (HTTP $code): ${e.message}');
        }
      } catch (e) {
        remaining.add(item);
        kept++;
        debugPrint('[credit-sms] upload error, retry later: $e');
      }
    }

    debugPrint('[credit-sms] flush: ${q.length} queued -> '
        '$uploaded uploaded, $dropped dropped, $kept kept');
    await _writeQueue(remaining);
    await _writeSeen(seen);
  }
}

/// Orchestrates SMS permission, inbox scanning, live incoming-SMS listening, and
/// draining the outbox. Android-only (iOS forbids reading SMS); on iOS every
/// method is a safe no-op.
class CreditSmsService {
  CreditSmsService(this._repo);

  final CreditSmsRepository _repo;
  final CreditSmsOutbox _outbox = CreditSmsOutbox();
  final Telephony _telephony = Telephony.instance;

  bool _listening = false;
  Timer? _flushTimer;

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// Whether the OS SMS read permission is currently held (no prompt).
  Future<bool> hasPermission() async {
    if (!_supported) return false;
    return Permission.sms.isGranted;
  }

  /// Ask for SMS permissions (READ_SMS + RECEIVE_SMS only — no phone perms,
  /// which aren't declared in the manifest). Returns true if granted.
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    final granted = await _telephony.requestSmsPermissions;
    return granted ?? false;
  }

  /// Begin live listening + an initial recent-inbox scan, and start periodic
  /// flushing. Call after consent is GRANTED and permission is held.
  Future<void> start() async {
    if (!_supported) {
      debugPrint('[credit-sms] start skipped: not Android');
      return;
    }
    if (_listening) {
      debugPrint('[credit-sms] already listening; re-scanning inbox');
      await scanInbox();
      return;
    }
    if (!await hasPermission()) {
      debugPrint('[credit-sms] start aborted: SMS permission not granted');
      return;
    }
    _listening = true;
    debugPrint('[credit-sms] starting: listen + inbox scan');

    _telephony.listenIncomingSms(
      onNewMessage: _onIncoming,
      // Foreground-only for reliability. Background delivery needs a top-level
      // @pragma('vm:entry-point') handler and is intentionally opt-in (see docs).
      listenInBackground: false,
    );

    await scanInbox();
    await flush();

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(minutes: 15), (_) => flush());
  }

  /// Stop listening and cancel periodic flush (call on consent revoke).
  void stop() {
    _listening = false;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Scan recent inbox messages (default last ~30 days) and enqueue any credits.
  Future<void> scanInbox({Duration window = const Duration(days: 30)}) async {
    if (!_supported) return;
    if (!await hasPermission()) {
      debugPrint('[credit-sms] scanInbox aborted: SMS permission not granted');
      return;
    }
    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    );
    final cutoff = DateTime.now().subtract(window).millisecondsSinceEpoch;
    var inWindow = 0;
    var credits = 0;
    for (final m in messages) {
      final dateMs = m.date ?? 0;
      if (dateMs < cutoff) continue;
      inWindow++;
      if (await _ingest(m.address, m.body, dateMs)) credits++;
    }
    debugPrint('[credit-sms] scanInbox: ${messages.length} total, '
        '$inWindow in window, $credits credit(s) queued');
    await flush();
  }

  Future<void> _onIncoming(SmsMessage message) async {
    debugPrint('[credit-sms] incoming SMS from ${message.address}');
    await _ingest(message.address, message.body,
        message.date ?? DateTime.now().millisecondsSinceEpoch);
    await flush();
  }

  /// Parse + enqueue one message. Returns true if it was a (new) credit SMS.
  Future<bool> _ingest(String? address, String? body, int dateMs) async {
    if (body == null || body.isEmpty) return false;
    final parsed = CreditSmsParser.parse(
      body: body,
      sender: address,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(dateMs),
    );
    if (parsed == null) return false; // not a credit SMS
    return _outbox.enqueue(parsed);
  }

  /// Drain the outbox now (e.g. on app resume / manual refresh).
  Future<void> flush() => _outbox.flush(_repo);

  Future<int> pendingCount() => _outbox.pendingCount();
}

final creditSmsServiceProvider = Provider<CreditSmsService>(
  (ref) => CreditSmsService(ref.watch(creditSmsRepositoryProvider)),
);
