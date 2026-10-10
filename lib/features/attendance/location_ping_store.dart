import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'location_ping_models.dart';

/// A durable FIFO queue of unsent location pings, persisted as one JSON line
/// per ping so the GPS trail survives an app restart or a long offline stretch.
///
/// Every captured ping is appended here the moment it is captured; entries are
/// removed only once the server has confirmed them (by client id), so nothing
/// is dropped when the employee has no internet — the queue simply drains when
/// connectivity returns. A corrupt line is skipped, never the whole file.
///
/// Why JSON Lines and not one JSON document: at a 5-second capture cadence the
/// old design re-read and re-wrote the whole document on every capture (a
/// megabyte every 5 s after a few hours offline). Appending a line is O(1); the
/// file is only rewritten when confirmed pings are removed.
///
/// The file is shared between the UI isolate and the background tracking
/// service isolate. Every operation takes an OS file lock on a sibling `.lock`
/// file, so the two isolates can never interleave a read-modify-write and lose
/// each other's pings.
class LocationPingStore {
  LocationPingStore._();
  static final LocationPingStore instance = LocationPingStore._();

  /// A store rooted at [directory] — for tests, which have no platform channel.
  @visibleForTesting
  LocationPingStore.inDirectory(Directory directory) : _dir = directory;

  static const _fileName = 'pending_location_pings.jsonl';
  static const _lockName = 'pending_location_pings.lock';
  /// The pre-JSONL single-document queue; imported once, then deleted.
  static const _legacyFileName = 'pending_location_pings.json';

  /// Safety cap so a device that is offline for a very long time can't grow the
  /// file without bound. ~100k pings ≈ 6 days of continuous 5-second capture;
  /// the oldest are dropped first if ever exceeded.
  static const int maxEntries = 100000;

  /// Leftovers older than this can no longer be placed on a meaningful route
  /// (the raw trail ages out server-side at 90 days) and are purged on sweep.
  static const Duration maxAge = Duration(days: 30);

  Directory? _dir;
  File? _file;
  File? _lockFile;
  // Serialises operations within this isolate; the file lock serialises across isolates.
  Future<void> _lock = Future<void>.value();

  Future<Directory> _resolveDir() async {
    return _dir ??= await getApplicationSupportDirectory();
  }

  Future<File> _resolveFile() async {
    if (_file != null) return _file!;
    final dir = await _resolveDir();
    _file = File('${dir.path}/$_fileName');
    return _file!;
  }

  Future<File> _resolveLockFile() async {
    if (_lockFile != null) return _lockFile!;
    final dir = await _resolveDir();
    _lockFile = File('${dir.path}/$_lockName');
    return _lockFile!;
  }

  /// Runs [op] holding the cross-isolate file lock. A lock failure (exotic file
  /// system) falls back to running unlocked rather than blocking tracking.
  Future<T> _withFileLock<T>(Future<T> Function() op) async {
    RandomAccessFile? raf;
    try {
      final lf = await _resolveLockFile();
      raf = await lf.open(mode: FileMode.write);
      await raf.lock(FileLock.blockingExclusive);
    } catch (e) {
      if (kDebugMode) debugPrint('LocationPingStore lock unavailable: $e');
      raf = null;
    }
    try {
      return await op();
    } finally {
      if (raf != null) {
        try {
          await raf.unlock();
        } catch (_) {}
        try {
          await raf.close();
        } catch (_) {}
      }
    }
  }

  Future<T> _run<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await _withFileLock(op));
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  static String _encode(_QueuedPing e) => jsonEncode(e.toJson());

  /// Reads every entry, skipping lines that cannot be parsed (a crash mid-write
  /// leaves at most one truncated line; it must not take the queue with it).
  Future<List<_QueuedPing>> _read() async {
    await _migrateLegacy();
    final f = await _resolveFile();
    if (!await f.exists()) return <_QueuedPing>[];
    final out = <_QueuedPing>[];
    try {
      final lines = await f.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          out.add(_QueuedPing.fromJson(jsonDecode(line) as Map<String, dynamic>));
        } catch (_) {
          // one bad line, skipped
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('LocationPingStore read failed: $e');
    }
    return out;
  }

  static Future<bool> _lacksTrailingNewline(File f) async {
    try {
      final len = await f.length();
      if (len == 0) return false;
      final raf = await f.open(mode: FileMode.read);
      try {
        await raf.setPosition(len - 1);
        final last = await raf.readByte();
        return last != 0x0A;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Rewrites the whole file atomically (temp file + rename).
  Future<void> _rewrite(List<_QueuedPing> entries) async {
    final f = await _resolveFile();
    final tmp = File('${f.path}.tmp');
    final sink = tmp.openWrite();
    for (final e in entries) {
      sink.writeln(_encode(e));
    }
    await sink.flush();
    await sink.close();
    await tmp.rename(f.path);
  }

  /// Imports a queue written by the previous single-document format.
  Future<void> _migrateLegacy() async {
    try {
      final dir = await _resolveDir();
      final legacy = File('${dir.path}/$_legacyFileName');
      if (!await legacy.exists()) return;
      final raw = await legacy.readAsString();
      final f = await _resolveFile();
      if (raw.trim().isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final list = (data['entries'] as List?) ?? const [];
        final sink = f.openWrite(mode: FileMode.append);
        if (await _lacksTrailingNewline(f)) sink.writeln();
        for (final e in list) {
          try {
            sink.writeln(_encode(_QueuedPing.fromJson(e as Map<String, dynamic>)));
          } catch (_) {}
        }
        await sink.flush();
        await sink.close();
      }
      await legacy.delete();
    } catch (e) {
      if (kDebugMode) debugPrint('LocationPingStore legacy import failed: $e');
    }
  }

  /// Append newly captured pings for [employeeId] to the durable queue.
  /// An append never re-reads the file; the size cap is enforced on the next
  /// rewrite (confirmation / purge).
  Future<void> append(int employeeId, List<LocationPing> pings) => _run(() async {
        if (pings.isEmpty) return;
        await _migrateLegacy();
        final f = await _resolveFile();
        final sink = f.openWrite(mode: FileMode.append);
        // A crash mid-write can leave the file without its final newline; the
        // next line must not be glued onto that fragment and lost with it.
        if (await _lacksTrailingNewline(f)) sink.writeln();
        for (final p in pings) {
          sink.writeln(_encode(_QueuedPing(employeeId, p)));
        }
        await sink.flush();
        await sink.close();
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
      removeByIds(
        employeeId,
        confirmed.map((p) => p.clientPingId).whereType<String>().toSet(),
        withoutId: confirmed.where((p) => p.clientPingId == null).length,
      );

  /// Remove the pings whose client ids the server acknowledged (accepted or
  /// duplicate) — or, for id-less legacy pings, the oldest [withoutId] of them.
  Future<void> removeByIds(int employeeId, Set<String> ids, {int withoutId = 0}) =>
      _run(() async {
        if (ids.isEmpty && withoutId <= 0) return;
        final entries = await _read();
        var remaining = withoutId;
        final before = entries.length;
        entries.removeWhere((e) {
          if (e.employeeId != employeeId) return false;
          final id = e.ping.clientPingId;
          if (id != null) return ids.contains(id);
          if (remaining > 0) {
            remaining--;
            return true;
          }
          return false;
        });
        if (entries.length > maxEntries) {
          entries.removeRange(0, entries.length - maxEntries);
        }
        if (entries.length != before) await _rewrite(entries);
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
        await _rewrite(entries);
      });

  /// Drops entries recorded more than [maxAge] ago — leftovers no login on
  /// this device will ever be able to upload — and enforces [maxEntries].
  /// Returns how many were removed.
  Future<int> purgeStale() => _run(() async {
        final entries = await _read();
        final cutoff = DateTime.now().toUtc().subtract(maxAge);
        final before = entries.length;
        entries.removeWhere((e) => e.ping.recordedAt.isBefore(cutoff));
        if (entries.length > maxEntries) {
          entries.removeRange(0, entries.length - maxEntries);
        }
        if (entries.length != before) await _rewrite(entries);
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
