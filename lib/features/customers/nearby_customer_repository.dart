// ─────────────────────────────────────────────────────────────────────────────
//  Nearby Customers data access.
//
//  Field employees work where the network doesn't, so results are cached on the
//  device and served when a request fails — but always tagged with the server
//  time they were produced, so the screen can say "showing data from 10:42"
//  instead of quietly presenting stale customers as current.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_client.dart';
import 'nearby_customer_models.dart';

class NearbyCustomerRepository {
  NearbyCustomerRepository(this._api);

  final ApiClient _api;

  /// Cached customer data is personal data, so it lives in encrypted storage
  /// alongside the auth token rather than in plain preferences.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kCache = 'nearby.customers.cache';
  static const _kConfig = 'nearby.config.cache';

  /// Authorised customers around a point. On a network failure the last cached
  /// page is returned with [NearbyCustomersResult.fromCache] set, so the
  /// employee keeps working and the UI can be explicit about what they're
  /// looking at. Rethrows when there is nothing cached to fall back on.
  Future<NearbyCustomersResult> nearby({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    CustomerCategory? category,
    String? search,
  }) async {
    try {
      final result = await _api.get<NearbyCustomersResult>(
        '/api/customers/nearby',
        query: {
          'latitude': latitude,
          'longitude': longitude,
          'radius': radiusMeters,
          if (category != null) 'category': category.wire,
          if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
        },
        parse: (d) => NearbyCustomersResult.fromJson(d as Map<String, dynamic>),
      );
      // Only an unfiltered page is worth caching: it's the one that can stand in
      // for any narrower view, and caching a search would make the fallback
      // depend on whatever was typed last.
      if ((search == null || search.trim().isEmpty) && category == null) {
        await _writeCache(result);
      }
      return result;
    } catch (_) {
      final cached = await readCache();
      if (cached != null) return cached.asCached();
      rethrow;
    }
  }

  /// Server-side tuning (radii, cadence). Falls back to the cached copy, then to
  /// compiled-in defaults — tracking must never depend on a reachable server.
  Future<FieldVisitConfig> config() async {
    try {
      final cfg = await _api.get<FieldVisitConfig>(
        '/api/customers/nearby/config',
        parse: (d) => FieldVisitConfig.fromJson(d as Map<String, dynamic>),
      );
      await _storage.write(key: _kConfig, value: jsonEncode(cfg.toJson()));
      return cfg;
    } catch (_) {
      final raw = await _storage.read(key: _kConfig);
      if (raw == null) return FieldVisitConfig.fallback;
      try {
        return FieldVisitConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        return FieldVisitConfig.fallback;
      }
    }
  }

  /// Suggests a corrected position for a customer (goes to an approver).
  Future<void> suggestLocation({
    required int customerId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    String? reason,
  }) {
    return _api.post<void>(
      '/api/customer-location/correction',
      body: {
        'customerId': customerId,
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      parse: (_) {},
    );
  }

  Future<NearbyCustomersResult?> readCache() async {
    try {
      final raw = await _storage.read(key: _kCache);
      if (raw == null) return null;
      return NearbyCustomersResult.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(NearbyCustomersResult result) async {
    try {
      await _storage.write(key: _kCache, value: jsonEncode(result.toJson()));
    } catch (_) {
      // A cache write failure must never break the screen.
    }
  }

  /// Drops cached customer data — called on logout so a shared handset doesn't
  /// keep one employee's book readable to the next.
  static Future<void> clearCache() async {
    try {
      await _storage.delete(key: _kCache);
    } catch (_) {}
  }
}

final nearbyCustomerRepositoryProvider = Provider<NearbyCustomerRepository>(
  (ref) => NearbyCustomerRepository(ref.watch(apiClientProvider)),
);

/// Server tuning, fetched once per app session.
final fieldVisitConfigProvider = FutureProvider<FieldVisitConfig>(
  (ref) => ref.watch(nearbyCustomerRepositoryProvider).config(),
);
