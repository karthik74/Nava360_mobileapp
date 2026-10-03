import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'location_ping_models.dart';

/// A durable FIFO queue of unsent location pings, persisted to a JSON file so the
/// GPS trail survives an app restart or a long offline stretch.
///
/// Every captured ping is appended here the moment it is captured; entries are
/// removed only once the server has confirmed them, so nothing is dropped when
/// the employee has no internet — the queue simply drains when connectivity
/// returns.
///
/// The file is shared between the UI isolate and the background tracking
/// service isolate (which is the writer while a session is running). Nothing is
/// cached across operations: each call re-reads the file, so one isolate can
/// never overwrite the other's work with a stale in-memory copy. Within an
/// isolate, operations are serialised through a future chain.
///
/// Pings are tagged with their employee id so a queue left over from a previous
/// session still uploads against the right employee.
class LocationPingStore {
  LocationPingStore._();
  static final LocationPingStore instance = LocationPingStore._();

  static const _fileName = 'pending_location_pings.json';

  /// Safety cap so a device that is offline for a very long time can't grow the
  /// file without bound. ~20k pings ≈ a week of dense capture; the oldest are
  /// dropped first if ever exceeded.
  static const int _maxEntries = 20000;

  /// Leftovers older than this can no longer be placed on a meaningful route
  /// (the raw trail ages out server-side anyway) and are purged on sweep.
  static const Duration maxAge = Duration(days: 7);

  File? _file;
  // Serialises all operations within this isolate so concurrent writes can't
  // interleave.
  Future<void> _lock = Future<void>.value();

  Future<File> _resolveFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/$_fileName');
    return _file!;
  }

  Future<List<_QueuedPing>> _read() async {
    try {
      final f = await _resolveFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        if (raw.trim().isNotEmpty) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final list = (data['entries'] as List?) ?? const [];
          return list
              .map((e) => _QueuedPing.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      // Corrupt/unreadable queue: start fresh rather than crash tracking.
      if (kDebugMode) debugPrint('LocationPingStore load failed: $e');
    }
    return <_QueuedPing>[];
  }

  Future<void> _persist(List<_QueuedPing> entries) async {
    final f = await _resolveFile();
    final data = jsonEncode({
      'v': 1,
      'entries': entries.map((e) => e.toJson()).toList(),
    });
    // Write to a temp file then rename, so a crash mid-write can't truncate the queue.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }

  Future<T> _run<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await op());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Append newly captured pings for [employeeId] to the durable queue.
  Future<void> append(int employeeId, List<LocationPing> pings) => _run(() async {
        if (pings.isEmpty) return;
        final entries = await _read();
        for (final p in pings) {
          entries.add(_QueuedPing(employeeId, p));
        }
        if (entries.length > _maxEntries) {
          entries.removeRange(0, entries.length - _maxEntries);
        }
        await _persist(entries);
      });

  /// All queued pings for [employeeId], oldest first.
  Future<List<LocationPing>> load(int employeeId) => _run(() async {
        final entries = await _read();
        return entries
            .where((e) => e.employeeId == employeeId)
            .map((e) => e.ping)
            .toList();
      });

  /// Queued pings grouped by employee (for a startup sweep of leftover pings).
  Future<Map<int, List<LocationPing>>> loadGrouped() => _run(() async {
        final entries = await _read();
        final map = <int, List<LocationPing>>{};
        for (final e in entries) {
          (map[e.employeeId] ??= <LocationPing>[]).add(e.ping);
        }
        return map;
      });

  /// Remove the pings the server just confirmed, matched by client id so a
  /// concurrent append from another isolate can never make us drop the wrong
  /// ones. Pings without an id fall back to oldest-first removal.
  Future<void> removeConfirmed(int employeeId, List<LocationPing> confirmed) =>
      _run(() async {
        if (confirmed.isEmpty) return;
        final entries = await _read();
        final ids = confirmed
            .map((p) => p.clientPingId)
            .whereType<String>()
            .toSet();
        var withoutId = confirmed.where((p) => p.clientPingId == null).length;
        entries.removeWhere((e) {
          if (e.employeeId != employeeId) return false;
          final id = e.ping.clientPingId;
          if (id != null) return ids.contains(id);
          if (withoutId > 0) {
            withoutId--;
            return true;
          }
          return false;
        });
        await _persist(entries);
      });

  /// Remove the oldest [count] pings for [employeeId]. Kept for callers that
  /// upload a slice they loaded themselves; prefer [removeConfirmed].
  Future<void> removeOldest(int employeeId, int count) => _run(() async {
        if (count <= 0) return;
        final entries = await _read();
        var removed = 0;
        entries.removeWhere((e) {
          if (removed >= count) return false;
          if (e.employeeId == employeeId) {
            removed++;
            return true;
          }
          return false;
        });
        await _persist(entries);
      });

  /// Drops entries recorded more than [maxAge] ago — leftovers no login on
  /// this device will ever be able to upload. Returns how many were removed.
  Future<int> purgeStale() => _run(() async {
        final entries = await _read();
        final cutoff = DateTime.now().toUtc().subtract(maxAge);
        final before = entries.length;
        entries.removeWhere((e) => e.ping.recordedAt.isBefore(cutoff));
        if (entries.length != before) await _persist(entries);
        return before - entries.length;
      });

  /// Queued pings for one employee — for diagnostics/state display.
  Future<int> countFor(int employeeId) => _run(() async =>
      (await _read()).where((e) => e.employeeId == employeeId).length);

  /// Total queued pings (all employees).
  Future<int> count() => _run(() async => (await _read()).length);
}

class _QueuedPing {
  final int employeeId;
  final LocationPing ping;
  _QueuedPing(this.employeeId, this.ping);

  Map<String, dynamic> toJson() => {'e': employeeId, 'p': ping.toJson()};

  static _QueuedPing fromJson(Map<String, dynamic> j) => _QueuedPing(
        (j['e'] as num).toInt(),
        LocationPing.fromJson(j['p'] as Map<String, dynamic>),
      );
}
