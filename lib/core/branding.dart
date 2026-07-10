import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'secure_storage.dart';
import 'theme.dart';

/// Runtime company branding — mirrors the web app's `src/lib/branding.ts`.
///
/// The backend exposes an unauthenticated `GET /api/public/branding` payload
/// (company identity, theme color, enabled modules, feature flags, org
/// terminology, dashboard-widget config). The app fetches it at startup,
/// caches the JSON locally for an instant branded first paint on the next
/// launch, and re-applies whenever a fresh copy arrives. The app itself ships
/// with NO hardcoded company identity — only neutral product defaults.
class Branding {
  final String productName;
  final String companyName;
  final String companyShortName;
  final String website;
  final String logoUrl;
  final String supportEmail;
  final String supportPhone;
  final String termsUrl;
  final String privacyUrl;

  /// Runtime brand color (hex, e.g. `#1D4ED8`); blank = product default.
  final String primaryColor;

  /// Enabled module codes; EMPTY = all modules enabled.
  final List<String> enabledModules;

  /// Feature flags keyed by SettingKey name (e.g. `FEATURE_CHAT`).
  final Map<String, bool> features;

  /// Org-hierarchy terminology (state/region/division/area/branch/…).
  final Map<String, String> terms;

  /// Raw dashboard-widget JSON (`{"hidden":[...]}`); blank = all shown.
  final String dashboardWidgets;

  /// Which optional org levels this company uses (keys: `state`, `area`).
  final Map<String, bool> orgLevels;

  const Branding({
    this.productName = 'Nava360',
    this.companyName = '',
    this.companyShortName = '',
    this.website = '',
    this.logoUrl = '',
    this.supportEmail = '',
    this.supportPhone = '',
    this.termsUrl = '',
    this.privacyUrl = '',
    this.primaryColor = '',
    this.enabledModules = const [],
    this.features = const {},
    this.terms = const {},
    this.dashboardWidgets = '',
    this.orgLevels = const {},
  });

  static const defaults = Branding();

  /// Latest applied branding, readable without a Riverpod ref — for pure
  /// helpers like the menu config. Kept in sync by [BrandingNotifier].
  static Branding current = defaults;

  static const Map<String, String> _defaultTerms = {
    'state': 'State',
    'region': 'Region',
    'division': 'Division',
    'area': 'Area',
    'branch': 'Branch',
    'department': 'Department',
    'designation': 'Designation',
  };

  factory Branding.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] as String?)?.trim() ?? '';
    return Branding(
      productName: s('productName').isEmpty ? 'Nava360' : s('productName'),
      companyName: s('companyName'),
      companyShortName: s('companyShortName'),
      website: s('website'),
      logoUrl: s('logoUrl'),
      supportEmail: s('supportEmail'),
      supportPhone: s('supportPhone'),
      termsUrl: s('termsUrl'),
      privacyUrl: s('privacyUrl'),
      primaryColor: s('primaryColor'),
      enabledModules: (j['enabledModules'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      features: (j['features'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v == true)) ??
          const {},
      terms: (j['terms'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          const {},
      dashboardWidgets: s('dashboardWidgets'),
      orgLevels: (j['orgLevels'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v == true)) ??
          const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'productName': productName,
        'companyName': companyName,
        'companyShortName': companyShortName,
        'website': website,
        'logoUrl': logoUrl,
        'supportEmail': supportEmail,
        'supportPhone': supportPhone,
        'termsUrl': termsUrl,
        'privacyUrl': privacyUrl,
        'primaryColor': primaryColor,
        'enabledModules': enabledModules,
        'features': features,
        'terms': terms,
        'dashboardWidgets': dashboardWidgets,
        'orgLevels': orgLevels,
      };

  /// Feature flag — enabled unless the backend explicitly says `false`.
  bool featureEnabled(String key) => features[key] != false;

  /// Module toggle — enabled when the list is empty or contains the code.
  bool moduleEnabled(String code) =>
      enabledModules.isEmpty || enabledModules.contains(code);

  /// Optional org level (keys: `state`, `area`) — on unless explicitly off.
  bool orgLevelEnabled(String level) => orgLevels[level] != false;

  /// Company-configured label for an org level, falling back to the default.
  String term(String key) =>
      terms[key]?.trim().isNotEmpty == true ? terms[key]! : (_defaultTerms[key] ?? key);

  /// Dashboard-widget keys hidden by configuration.
  Set<String> get hiddenDashboardWidgets {
    if (dashboardWidgets.trim().isEmpty) return const {};
    try {
      final parsed = jsonDecode(dashboardWidgets);
      final hidden = (parsed is Map ? parsed['hidden'] : null) as List?;
      return hidden?.map((e) => e.toString()).toSet() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// Runtime brand color parsed from [primaryColor]; null = product default.
  Color? get brandColor {
    var hex = primaryColor.replaceAll('#', '').trim();
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final v = int.tryParse(hex, radix: 16);
    return v == null ? null : Color(v);
  }
}

/// Fetches, caches and exposes the deployment's branding. Bootstrapped once
/// from `main()`: cached copy first (instant), then the network copy.
class BrandingNotifier extends Notifier<Branding> {
  @override
  Branding build() => Branding.defaults;

  /// Cache-first load, then background refresh — mirrors the web app.
  Future<void> bootstrap() async {
    final cached = await SecureStorage.readBrandingJson();
    if (cached != null && cached.isNotEmpty) {
      try {
        _apply(Branding.fromJson(jsonDecode(cached) as Map<String, dynamic>));
      } catch (_) {
        // Corrupt cache — ignore; the network refresh below replaces it.
      }
    }
    await refresh();
  }

  /// Re-fetches from the backend (also used after settings change server-side).
  Future<void> refresh() async {
    try {
      final fresh = await ApiClient.instance.get<Branding>(
        '/api/public/branding',
        parse: (d) => Branding.fromJson(d as Map<String, dynamic>),
      );
      _apply(fresh);
      await SecureStorage.writeBrandingJson(jsonEncode(fresh.toJson()));
    } catch (_) {
      // Offline / server unreachable — keep whatever we have (cache/defaults).
    }
  }

  void _apply(Branding b) {
    Branding.current = b;
    AppColors.applyBrand(b.brandColor);
    state = b;
  }
}

final brandingProvider =
    NotifierProvider<BrandingNotifier, Branding>(BrandingNotifier.new);
