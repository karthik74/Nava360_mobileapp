import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/features/attendance/location_ping_models.dart';
import 'package:nava360/features/attendance/location_ping_store.dart';

/// The durable queue: append-only lines, confirmation by id, a corrupt line
/// never costs the queue, the legacy single-document file is imported once.
void main() {
  late Directory dir;
  late LocationPingStore store;

  LocationPing ping(int i) => LocationPing(
        clientPingId: '7-${1000 + i}-$i',
        recordedAt: DateTime.utc(2026, 10, 9, 4, 0, i),
        latitude: 15.3 + i * 0.0005,
        longitude: 75.12,
        accuracyMeters: 8,
        provider: 'FUSED',
        trackingState: i == 0 ? 'START' : 'MOVING',
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pingstore');
    store = LocationPingStore.inDirectory(dir);
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('append then load keeps order and every field', () async {
    await store.append(7, [ping(0), ping(1)]);
    await store.append(7, [ping(2)]);
    final loaded = await store.load(7);
    expect(loaded.map((p) => p.clientPingId), ['7-1000-0', '7-1001-1', '7-1002-2']);
    expect(loaded.first.trackingState, 'START');
    expect(loaded.first.recordedAt, DateTime.utc(2026, 10, 9, 4, 0, 0));
    expect(await store.countFor(7), 3);
  });

  test('removeByIds forgets exactly the acknowledged ids', () async {
    await store.append(7, [ping(0), ping(1), ping(2)]);
    await store.append(8, [ping(5)]); // another employee on the same phone
    await store.removeByIds(7, {'7-1000-0', '7-1002-2'});
    expect((await store.load(7)).map((p) => p.clientPingId), ['7-1001-1']);
    expect(await store.countFor(8), 1);
  });

  test('a corrupt line is skipped, the rest of the queue survives', () async {
    await store.append(7, [ping(0), ping(1)]);
    final f = File('${dir.path}/pending_location_pings.jsonl');
    await f.writeAsString('{"e":7,"p":{"broken', mode: FileMode.append);
    await store.append(7, [ping(2)]);
    final loaded = await store.load(7);
    expect(loaded.length, 3);
  });

  test('the legacy single-document queue is imported once', () async {
    final legacy = File('${dir.path}/pending_location_pings.json');
    await legacy.writeAsString(jsonEncode({
      'v': 1,
      'entries': [
        {'e': 7, 'p': ping(0).toJson()},
      ],
    }));
    await store.append(7, [ping(1)]);
    expect((await store.load(7)).map((p) => p.clientPingId), ['7-1000-0', '7-1001-1']);
    expect(await legacy.exists(), isFalse);
  });

  test('purgeStale drops only entries older than the retention window', () async {
    final old = LocationPing(
      clientPingId: 'old',
      recordedAt: DateTime.now().toUtc().subtract(const Duration(days: 40)),
      latitude: 15.3,
      longitude: 75.12,
    );
    await store.append(7, [old, ping(1)]);
    expect(await store.purgeStale(), 1);
    expect((await store.load(7)).map((p) => p.clientPingId), ['7-1001-1']);
  });
}
