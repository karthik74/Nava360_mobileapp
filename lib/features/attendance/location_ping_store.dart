import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'location_ping_models.dart';

/// A durable FIFO queue of unsent location pings, persisted to a JSON file so the
/// GPS trail survives an app restart or a long offline stretch.
///
/// The in-memory [LocationTracker] buffer is lost the moment the OS kills the
/// process (very common for a backgrounded location app). Every captured ping is
/// therefore also appended here; entries are removed only once the server has
/// confirmed them, so nothing is dropped when the employee has no internet — the
/// queue simply drains when connectivity returns (on the next flush, the next
/// check-in, or app start).
///
/// Pings are tagged with their {@code employeeId} so a queue left over from a
/// previous session still uploads against the right employee.
class LocationPingStore {
  LocationPingStore._();
  static final LocationPingStore instance = LocationPingStore._();

  static const _fileName = 'pending_location_pings.json';

  /// Safety cap so a device that is offline for a very long time can't grow the
  /// file without bound. ~20k pings ≈ weeks at the 5-minute default cadence; the
  /// oldest are dropped first if ever exceeded.
  static const int _maxEntries = 20000;

  File? _file;
  List<_QueuedPing>? _cache;
  // Serialises all mutating operations so concurrent file writes can't corrupt it.
  Future<void> _lock = Future<void>.value();

  Future<File> _resolveFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/$_fileName');
    return _file!;
  }

  Future<List<_QueuedPing>> _loadCache() async {
    if (_cache != null) return _cache!;
    try {
      final f = await _resolveFile();
      if (await f.exists()) {
        final raw = await f.readAsString();
        if (raw.trim().isNotEmpty) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final list = (data['entries'] as List?) ?? const [];
          _cache = list
              .map((e) => _QueuedPing.fromJson(e as Map<String, dynamic>))
              .toList();
          return _cache!;
        }
      }
    } catch (e) {
      // Corrupt/unreadable queue: start fresh rather than crash tracking.
      if (kDebugMode) debugPrint('LocationPingStore load failed: $e');
    }
    _cache = <_QueuedPing>[];
    return _cache!;
  }

  Future<void> _persist() async {
    final f = await _resolveFile();
    final entries = _cache ?? const <_QueuedPing>[];
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
        final cache = await _loadCache();
        for (final p in pings) {
          cache.add(_QueuedPing(employeeId, p));
        }
        if (cache.length > _maxEntries) {
          cache.removeRange(0, cache.length - _maxEntries);
        }
        await _persist();
      });

  /// All queued pings for [employeeId], oldest first.
  Future<List<LocationPing>> load(int employeeId) => _run(() async {
        final cache = await _loadCache();
        return cache
            .where((e) => e.employeeId == employeeId)
            .map((e) => e.ping)
            .toList();
      });

  /// Queued pings grouped by employee (for a startup sweep of leftover pings).
  Future<Map<int, List<LocationPing>>> loadGrouped() => _run(() async {
        final cache = await _loadCache();
        final map = <int, List<LocationPing>>{};
        for (final e in cache) {
          (map[e.employeeId] ??= <LocationPing>[]).add(e.ping);
        }
        return map;
      });

  /// Remove the oldest [count] pings for [employeeId] — the ones just confirmed
  /// by the server. FIFO, so newly captured pings during an in-flight upload stay.
  Future<void> removeOldest(int employeeId, int count) => _run(() async {
        if (count <= 0) return;
        final cache = await _loadCache();
        var removed = 0;
        cache.removeWhere((e) {
          if (removed >= count) return false;
          if (e.employeeId == employeeId) {
            removed++;
            return true;
          }
          return false;
        });
        await _persist();
      });

  /// Total queued pings (all employees) — for diagnostics/state display.
  Future<int> count() => _run(() async => (await _loadCache()).length);
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
