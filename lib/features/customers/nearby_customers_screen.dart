// ─────────────────────────────────────────────────────────────────────────────
//  Nearby Customers (route /nearby-customers).
//
//  The employee's authorised customers around their current position, on an
//  OpenStreetMap map and in a distance-sorted list. Marker colour is the
//  collections category: red NPA, yellow overdue, green regular.
//
//  Two deliberate behaviours:
//   • The list refreshes only when the employee has actually moved a meaningful
//     distance, or pulls to refresh. Re-querying on every GPS tick would make
//     the markers flicker and burn data for no new information.
//   • Nothing is ever shown as current when it isn't. Cached results carry the
//     server time they were produced, and the banner says so.
//
//  Uses flutter_map + OSM raster tiles (same as the MIS branch locator) so no
//  Maps API key or Play Services dependency is introduced. Clustering is done
//  here on a zoom-aware grid rather than by adding another package.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/pro_ui.dart';
import '../attendance/location_tracker.dart';
import '../auth/auth_controller.dart';
import 'customer_detail_screen.dart';
import 'customer_models.dart';
import 'customer_repository.dart';
import 'nearby_customer_models.dart';
import 'nearby_customer_repository.dart';

class NearbyCustomersScreen extends ConsumerStatefulWidget {
  const NearbyCustomersScreen({super.key});

  @override
  ConsumerState<NearbyCustomersScreen> createState() =>
      _NearbyCustomersScreenState();
}

class _NearbyCustomersScreenState extends ConsumerState<NearbyCustomersScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();

  Position? _position;
  /// Position the current results were fetched for — the yardstick for
  /// "has the employee moved enough to be worth refetching?".
  LatLng? _fetchedFor;

  FieldVisitConfig _config = FieldVisitConfig.fallback;
  int _radius = FieldVisitConfig.fallback.defaultRadiusMeters;
  final Set<CustomerCategory> _categories = {};
  String _search = '';
  Timer? _searchDebounce;

  /// "All customers" search — every customer the employee may see, including
  /// the ones with no location (which can never appear in the nearby list).
  /// This is how a field employee finds such a customer and captures its pin.
  List<Customer> _allMatches = const [];
  bool _searchingAll = false;
  String _allMatchesFor = '';
  Timer? _allDebounce;

  NearbyCustomersResult? _result;
  bool _loading = true;
  String? _error;
  /// Set when location can't be read — permission, GPS off, or a timeout.
  String? _locationProblem;
  bool _permissionDenied = false;

  double _zoom = 14;

  /// Refetch once the employee is this far from where the last results were
  /// fetched. Below this the list wouldn't meaningfully change.
  static const _refetchAfterMeters = 250.0;

  /// Accuracy beyond which we warn that positions may be unreliable.
  static const _lowAccuracyMeters = 100.0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _allDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final cfg = await ref.read(nearbyCustomerRepositoryProvider).config();
    if (!mounted) return;
    setState(() {
      _config = cfg;
      _radius = cfg.defaultRadiusMeters;
    });
    // Push the server's cadence into the tracker. Without this the app samples
    // GPS every few minutes when stationary, which is far too slow to observe a
    // two-minute customer visit.
    ref.read(locationTrackerProvider.notifier).applyConfig(
          movingSeconds: cfg.trackIntervalMovingSeconds,
          stationarySeconds: cfg.trackIntervalStationarySeconds,
          nearCustomerSeconds: cfg.trackIntervalNearCustomerSeconds,
          nearCustomerRadiusMeters: cfg.trackNearCustomerRadiusMeters,
          minDisplacementMeters: cfg.trackMinDisplacementMeters,
        );
    await _locateAndLoad();
  }

  // ── Location ─────────────────────────────────────────────────────────────

  Future<void> _locateAndLoad({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _locationProblem = null;
    });

    final pos = await _currentPosition();
    if (!mounted) return;
    if (pos == null) {
      setState(() => _loading = false);
      // Fall back to whatever was cached so the screen still has content.
      final cached = await ref.read(nearbyCustomerRepositoryProvider).readCache();
      if (mounted && cached != null && _result == null) {
        setState(() => _result = cached.asCached());
      }
      return;
    }

    final here = LatLng(pos.latitude, pos.longitude);
    final moved = _fetchedFor == null
        ? double.infinity
        : const Distance().as(LengthUnit.Meter, _fetchedFor!, here);

    setState(() => _position = pos);

    if (!force && moved < _refetchAfterMeters && _result != null) {
      // Same place: keep the existing results and just move the "you" marker.
      setState(() => _loading = false);
      return;
    }
    await _load(here);
  }

  /// Reads the device position, translating each failure into a message the
  /// employee can act on rather than a raw exception.
  Future<Position?> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _locationProblem = 'GPS is turned off.');
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      setState(() {
        _permissionDenied = true;
        _locationProblem =
            'Location permission is required to show nearby customers.';
      });
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (_) {
      // A cold GPS fix indoors can simply time out; the last known position is
      // better than an empty screen.
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        setState(() =>
            _locationProblem = 'Could not get your location. Try again outdoors.');
      }
      return last;
    }
  }

  Future<void> _load(LatLng at) async {
    try {
      final result = await ref.read(nearbyCustomerRepositoryProvider).nearby(
            latitude: at.latitude,
            longitude: at.longitude,
            radiusMeters: _radius,
            search: _search,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _fetchedFor = at;
        _loading = false;
      });
      // Let the tracker know where the customers are so it can sample GPS more
      // often near one. The coordinates stay on the device — they only decide
      // the capture interval.
      ref.read(locationTrackerProvider.notifier).setNearbyCustomerPoints([
        for (final c in result.customers)
          if (c.hasLocation) (lat: c.latitude!, lng: c.longitude!),
      ]);
      _fitToResults(at, result.customers);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load nearby customers. Pull down to retry.';
      });
    }
  }

  void _fitToResults(LatLng centre, List<NearbyCustomer> customers) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(centre, _zoomForRadius(_radius));
    });
  }

  Future<void> _searchAll(String term) async {
    if (!mounted) return;
    setState(() => _searchingAll = true);
    try {
      final list =
          await ref.read(customerRepositoryProvider).search(term, size: 30);
      if (!mounted || _search.trim() != term) return;
      setState(() {
        _allMatches = list;
        _allMatchesFor = term;
        _searchingAll = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allMatches = const [];
        _allMatchesFor = term;
        _searchingAll = false;
      });
    }
  }

  /// Metres from the employee to a searched customer's stored pin, if both are known.
  int? _distanceTo(Customer c) {
    final p = _position;
    if (p == null || !c.hasLocation) return null;
    return Geolocator.distanceBetween(
            p.latitude, p.longitude, c.latitude!, c.longitude!)
        .round();
  }

  /// Lets a searched customer use the same sheet (and location-capture block)
  /// as a nearby one. Distance is computed here; the server had none to give.
  NearbyCustomer _asNearby(Customer c) => NearbyCustomer(
        id: c.id,
        customerName: c.customerName,
        category: CustomerCategory.parse(null),
        distanceMeters: _distanceTo(c) ?? 0,
        customerCode: c.customerCode,
        mobileNumber: c.mobileNumber,
        address: c.address,
        latitude: c.hasLocation ? c.latitude : null,
        longitude: c.hasLocation ? c.longitude : null,
        locationStatus: c.locationStatus,
        branchId: c.branchId,
        branchName: c.branchName,
      );

  /// A zoom level that roughly frames the chosen radius.
  double _zoomForRadius(int metres) {
    if (metres <= 1000) return 15;
    if (metres <= 2000) return 14;
    if (metres <= 5000) return 13;
    if (metres <= 10000) return 12;
    return 11;
  }

  // ── Filtering (client-side; the server already applied authorisation) ─────

  List<NearbyCustomer> get _visible {
    final all = _result?.customers ?? const <NearbyCustomer>[];
    final term = _search.trim().toLowerCase();
    return all.where((c) {
      if (_categories.isNotEmpty && !_categories.contains(c.category)) {
        return false;
      }
      if (term.isEmpty) return true;
      return c.customerName.toLowerCase().contains(term) ||
          (c.customerCode ?? '').toLowerCase().contains(term) ||
          (c.mobileNumber ?? '').toLowerCase().contains(term) ||
          (c.village ?? '').toLowerCase().contains(term) ||
          (c.branchName ?? '').toLowerCase().contains(term);
    }).toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _search = value);
    });
    _allDebounce?.cancel();
    final term = value.trim();
    if (term.length < 2) {
      if (_allMatches.isNotEmpty || _searchingAll) {
        setState(() {
          _allMatches = const [];
          _searchingAll = false;
          _allMatchesFor = '';
        });
      }
      return;
    }
    _allDebounce = Timer(const Duration(milliseconds: 450), () => _searchAll(term));
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Starts turn-by-turn navigation to the customer in Google Maps.
  ///
  /// Only the coordinates are passed — never the customer's name, phone number
  /// or account details, which have no business leaving the app.
  ///
  /// Each candidate is ATTEMPTED rather than gated on [canLaunchUrl] alone:
  /// canLaunchUrl reports false for any scheme the platform hasn't been told we
  /// use (Android's <queries>, iOS's LSApplicationQueriesSchemes), so trusting
  /// it as the only check is how this button ends up claiming "no maps app" on
  /// a phone with Google Maps installed.
  Future<void> _navigateTo(NearbyCustomer c) async {
    if (!c.hasLocation) return;
    final lat = c.latitude!, lng = c.longitude!;

    final candidates = <Uri>[
      if (Platform.isAndroid)
        // Launches Google Maps straight into turn-by-turn guidance.
        Uri.parse('google.navigation:q=$lat,$lng&mode=d'),
      if (Platform.isIOS)
        // Google Maps app on iOS, already in driving-directions mode.
        Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving'),
      // Universal link: opens the Google Maps app on either platform when it is
      // installed, and the web version when it isn't. dir_action=navigate asks
      // it to begin guidance rather than just show the route.
      Uri.parse('https://www.google.com/maps/dir/?api=1'
          '&destination=$lat,$lng&travelmode=driving&dir_action=navigate'),
      if (Platform.isIOS) Uri.parse('maps://?daddr=$lat,$lng&dirflg=d'),
      // Last resort: whatever the device treats as its map handler.
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
    ];

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {
        // Not installed / not handled — fall through to the next candidate.
      }
    }
    if (!mounted) return;
    // No maps app: don't dead-end — offer the coordinates to copy.
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Navigation application is unavailable'),
        content: SelectableText(
            'No maps app could be opened on this device.\n\n'
            'Destination: $lat, $lng'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _call(NearbyCustomer c) async {
    final number = c.mobileNumber;
    if (number == null || number.trim().isEmpty) return;
    // Strip spaces/dashes — the dialer wants digits, + and the usual separators.
    final cleaned = number.replaceAll(RegExp(r'[^0-9+#*]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: cleaned);
    try {
      // Attempted directly for the same reason as navigation: canLaunchUrl is
      // false for tel: unless the DIAL intent is declared, even with a dialer.
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      _toast('Could not open the dialler.');
    } catch (_) {
      _toast('Could not open the dialler.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  String _radiusLabel(int metres) => metres < 1000
      ? '$metres m'
      : '${(metres / 1000).toStringAsFixed(metres % 1000 == 0 ? 0 : 1)} km';

  @override
  Widget build(BuildContext context) {
    final customers = _visible;
    final me = _position == null
        ? null
        : LatLng(_position!.latitude, _position!.longitude);
    final all = _result?.customers ?? const <NearbyCustomer>[];
    final radii = _config.radiusOptions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby customers'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _locateAndLoad(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ProPage(
        onRefresh: () => _locateAndLoad(force: true),
        hero: ProHero(
          title: 'Nearby customers',
          subtitle: 'Customers within ${_radiusLabel(_radius)} of you',
          overlap: ProSearchField(
            raised: true,
            controller: _searchController,
            onChanged: _onSearchChanged,
            hint: 'Search name, ID, mobile or village',
            onClear: () => setState(() => _search = ''),
          ),
          children: [
            if (_loading && _result != null)
              const ProLiveLine(text: 'Refreshing your position…')
            else if (_position != null && _locationProblem == null)
              ProLiveLine(
                text: 'Live position · ±${_position!.accuracy.round()} m',
                color: _position!.accuracy > _lowAccuracyMeters
                    ? const Color(0xFFF2B347)
                    : null,
              ),
            ProHeroStats(stats: [
              for (final c in CustomerCategory.values)
                ProStat(
                  label: c.label,
                  value: _result == null
                      ? '—'
                      : '${all.where((x) => x.category == c).length}',
                  sub: _categories.contains(c) ? 'filtering' : 'tap to filter',
                  dot: c.color,
                  selected: _categories.contains(c),
                  onTap: () => setState(() {
                    if (_categories.contains(c)) {
                      _categories.remove(c);
                    } else {
                      _categories.add(c);
                    }
                  }),
                ),
            ]),
          ],
        ),
        children: [
          ..._statusNotes(),
          if (radii.isNotEmpty)
            ProChipBar(
              labels: [for (final m in radii) _radiusLabel(m)],
              selected: radii.indexOf(_radius),
              onSelected: (i) {
                setState(() => _radius = radii[i]);
                if (_position != null) {
                  _load(LatLng(_position!.latitude, _position!.longitude));
                }
              },
              bleed: 0,
            ),
          if (!_config.nearbyCustomersEnabled)
            _message('Nearby Customers is not enabled for your company.')
          else ...[
            _map(me, customers),
            _legend(),
            _listHeader(customers.length),
            if (_loading && _result == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (customers.isEmpty)
              _message(_emptyMessage())
            else
              ProListGroup(
                dividerIndent: 66,
                children: [for (final c in customers) _customerTile(c)],
              ),
            ..._allCustomersSection(customers),
          ],
        ],
      ),
    );
  }

  /// "All customers" results for the current search: everyone the employee may
  /// see who is NOT already in the nearby list — outside the radius, or with no
  /// location at all. Tapping one opens the usual sheet, where a customer with
  /// no pin can have it captured from where the employee stands.
  List<Widget> _allCustomersSection(List<NearbyCustomer> nearby) {
    final term = _search.trim();
    if (term.length < 2) return const [];
    final nearbyIds = nearby.map((c) => c.id).toSet();
    final others =
        _allMatches.where((c) => !nearbyIds.contains(c.id)).toList();
    return [
      ProSectionHeader(
        title: 'All customers matching "$term"',
        small: true,
        trailing: _searchingAll
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
      if (!_searchingAll && _allMatchesFor == term && others.isEmpty)
        ProNote(
          _allMatches.isEmpty
              ? 'No other customers match.'
              : 'Every match is already in the nearby list above.',
        ),
      if (others.isNotEmpty)
        ProListGroup(
          children: [for (final c in others) _searchedCustomerTile(c)],
        ),
    ];
  }

  Widget _searchedCustomerTile(Customer c) {
    final metres = _distanceTo(c);
    final String badge;
    final Color tone;
    final IconData icon;
    if (!c.hasLocation) {
      badge = 'No location';
      tone = AppColors.warning;
      icon = Icons.location_off_rounded;
    } else if (metres == null) {
      badge = 'Outside radius';
      tone = AppColors.muted;
      icon = Icons.location_on_outlined;
    } else {
      badge = metres < 1000
          ? '$metres m away'
          : '${(metres / 1000).toStringAsFixed(metres < 10000 ? 1 : 0)} km away';
      tone = AppColors.muted;
      icon = Icons.location_on_outlined;
    }
    final sub = [
      c.customerCode,
      c.branchName,
      c.address,
    ].where((x) => x != null && x.trim().isNotEmpty).join(' · ');

    return ProListRow(
      onTap: () => _showCustomer(_asNearby(c)),
      leading: ProIconWell(icon: icon, color: tone),
      title: c.customerName,
      subtitle: sub.isEmpty ? null : sub,
      meta: badge,
      chevron: c.hasLocation,
      trailing: !c.hasLocation
          ? Icon(Icons.add_location_alt_rounded, color: AppColors.primary)
          : null,
    );
  }

  String _emptyMessage() {
    if (_error != null) return _error!;
    if (_locationProblem != null) return _locationProblem!;
    final km = (_radius / 1000).toStringAsFixed(_radius % 1000 == 0 ? 0 : 1);
    if (_search.isNotEmpty || _categories.isNotEmpty) {
      return 'No customers match your search within $km km.';
    }
    return 'No authorised customers found within $km km.';
  }

  /// Location / freshness / accuracy notes. Everything the employee needs to
  /// judge how much to trust what they're looking at.
  List<Widget> _statusNotes() {
    final messages = <_Status>[];
    if (_locationProblem != null) {
      messages.add(_Status(_locationProblem!, Icons.location_off_rounded,
          AppColors.danger, _permissionDenied ? 'Open settings' : null));
    } else if (_position != null) {
      final acc = _position!.accuracy;
      if (acc > _lowAccuracyMeters) {
        messages.add(_Status(
            'Location accuracy is currently low (±${acc.round()} m).',
            Icons.gps_not_fixed_rounded,
            AppColors.warning,
            null));
      }
    }
    final result = _result;
    if (result != null && result.fromCache) {
      messages.add(_Status(
          'Using customer data last updated at ${_time(result.generatedAt)}.',
          Icons.cloud_off_rounded,
          AppColors.warning,
          null));
    }
    if (result != null && result.truncated) {
      messages.add(_Status(
          'Showing the nearest ${result.maxResults}. Reduce the radius to see fewer, closer customers.',
          Icons.filter_alt_rounded,
          AppColors.muted,
          null));
    }
    return [for (final m in messages) _StatusNote(status: m)];
  }

  Widget _map(LatLng? me, List<NearbyCustomer> customers) {
    final centre = me ??
        (customers.isNotEmpty && customers.first.hasLocation
            ? LatLng(customers.first.latitude!, customers.first.longitude!)
            : const LatLng(20.5937, 78.9629)); // India, as a last resort

    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: centre,
            initialZoom: _zoomForRadius(_radius),
            onPositionChanged: (pos, _) {
              // Track zoom so clustering can loosen as the user zooms in,
              // without rebuilding the whole screen on every frame.
              final z = pos.zoom ?? _zoom;
              if ((z - _zoom).abs() >= 0.75) {
                setState(() => _zoom = z);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.nava360.app',
            ),
            if (me != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: me,
                  radius: _radius.toDouble(),
                  useRadiusInMeter: true,
                  color: AppColors.primary.withOpacity(0.06),
                  borderColor: AppColors.primary.withOpacity(0.35),
                  borderStrokeWidth: 1,
                ),
              ]),
            MarkerLayer(markers: _markers(me, customers)),
          ],
        ),
      ),
    );
  }

  List<Marker> _markers(LatLng? me, List<NearbyCustomer> customers) {
    final markers = <Marker>[];
    if (me != null) {
      markers.add(Marker(
        point: me,
        width: 26,
        height: 26,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 4),
            ],
          ),
        ),
      ));
    }

    for (final cluster in _cluster(customers)) {
      if (cluster.members.length == 1) {
        final c = cluster.members.first;
        markers.add(Marker(
          point: cluster.centre,
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: () => _showCustomer(c),
            child: _pin(c.category.color),
          ),
        ));
      } else {
        markers.add(Marker(
          point: cluster.centre,
          width: 40,
          height: 40,
          child: GestureDetector(
            // Tapping a cluster zooms in until it breaks apart.
            onTap: () => _mapController.move(
                cluster.centre, math.min(_zoom + 2.5, 18)),
            child: _clusterBubble(cluster),
          ),
        ));
      }
    }
    return markers;
  }

  Widget _pin(Color color) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 3),
          ],
        ),
      );

  Widget _clusterBubble(_Cluster cluster) {
    // Colour the bubble by its most serious member: an NPA hiding inside a
    // cluster shouldn't be invisible until you zoom in.
    final worst = cluster.members.any((c) => c.category == CustomerCategory.npa)
        ? CustomerCategory.npa
        : cluster.members.any((c) => c.category == CustomerCategory.overdue)
            ? CustomerCategory.overdue
            : CustomerCategory.regular;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: worst.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 3),
        ],
      ),
      child: Text('${cluster.members.length}',
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  /// Grid clustering: customers are bucketed onto a lat/lng grid whose cell size
  /// shrinks as the map zooms in, so a village of shared coordinates shows as
  /// one numbered bubble from afar and separates as you zoom.
  List<_Cluster> _cluster(List<NearbyCustomer> customers) {
    final withLocation = customers.where((c) => c.hasLocation).toList();
    if (withLocation.isEmpty) return const [];
    // ~60 px worth of degrees at the current zoom.
    final cell = 360 / math.pow(2, _zoom) * 0.25;
    final buckets = <String, List<NearbyCustomer>>{};
    for (final c in withLocation) {
      final key = '${(c.latitude! / cell).floor()}:${(c.longitude! / cell).floor()}';
      buckets.putIfAbsent(key, () => []).add(c);
    }
    return buckets.values.map((members) {
      final lat = members.map((c) => c.latitude!).reduce((a, b) => a + b) /
          members.length;
      final lng = members.map((c) => c.longitude!).reduce((a, b) => a + b) /
          members.length;
      return _Cluster(LatLng(lat, lng), members);
    }).toList();
  }

  Widget _legend() {
    Widget item(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label, style: AppText.caption),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          for (final c in CustomerCategory.values) item(c.color, c.label),
          item(AppColors.primary, 'You'),
        ],
      ),
    );
  }

  Widget _listHeader(int count) {
    final result = _result;
    return ProSectionHeader(
      title: '$count customer${count == 1 ? '' : 's'} by distance',
      small: true,
      trailing: result == null
          ? null
          : Text(
              result.fromCache
                  ? 'Cached ${_time(result.generatedAt)}'
                  : 'Updated ${_time(result.generatedAt)}',
              style: AppText.caption.merge(AppText.number),
            ),
    );
  }

  Widget _customerTile(NearbyCustomer c) {
    final sub = [c.customerCode, c.placeLabel]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');
    final money = [
      if (c.outstandingAmount != null)
        'Outstanding ₹${c.outstandingAmount!.toStringAsFixed(0)}',
      if (c.overdueDays != null) '${c.overdueDays} days overdue',
    ].join(' · ');
    final visit = c.lastVisitedAt == null
        ? null
        : c.visitedRecentlyByColleague
            ? 'A colleague visited ${_ago(c.lastVisitedAt!)}'
            : 'Last visit ${_ago(c.lastVisitedAt!)}';
    return ProListRow(
      onTap: () => _showCustomer(c),
      leading: ProAvatar(name: c.customerName, dot: c.category.color),
      title: c.customerName,
      subtitle: [if (sub.isNotEmpty) sub, if (visit != null) visit].join('\n'),
      meta: money.isEmpty ? null : money,
      value: c.distanceLabel,
      valueColor: AppColors.primary,
      pill: ProPill(c.category.label,
          color: _categoryInk(c.category), dot: true),
    );
  }

  /// Text-strength version of a category colour (readable on its tint).
  static Color _categoryInk(CustomerCategory c) {
    switch (c) {
      case CustomerCategory.npa:
        return AppColors.danger;
      case CustomerCategory.overdue:
        return const Color(0xFF9A5B00);
      case CustomerCategory.regular:
        return AppColors.success;
    }
  }

  void _showCustomer(NearbyCustomer c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 20 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFC6D3D6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ProAvatar(name: c.customerName, size: 44, dot: c.category.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(c.customerName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: AppColors.ink)),
                ),
                const SizedBox(width: 8),
                Text(c.hasLocation ? c.distanceLabel : 'No location',
                    style: AppText.number.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.hasLocation
                            ? AppColors.primary
                            : AppColors.warning)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              [
                c.customerCode,
                c.category.label,
                c.placeLabel,
              ].where((s) => s != null && s.isNotEmpty).join(' · '),
              style: AppText.caption,
            ),
            if (c.outstandingAmount != null || c.overdueDays != null) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (c.outstandingAmount != null)
                    'Outstanding ₹${c.outstandingAmount!.toStringAsFixed(0)}',
                  if (c.overdueDays != null) '${c.overdueDays} days overdue',
                ].join('   ·   '),
                style: AppText.number.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _categoryInk(c.category)),
              ),
            ],
            if (c.lastVisitedByMeAt != null) ...[
              const SizedBox(height: 8),
              Text('You last visited ${_ago(c.lastVisitedByMeAt!)}',
                  style: AppText.caption),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: c.hasLocation
                        ? () {
                            Navigator.pop(ctx);
                            _navigateTo(c);
                          }
                        : null,
                    icon: const Icon(Icons.directions_rounded, size: 18),
                    label: const Text('Navigate'),
                  ),
                ),
                // Only rendered when the server sent a number — i.e. when the
                // employee is permitted to see contact details at all.
                if (c.mobileNumber != null && c.mobileNumber!.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _call(c);
                      },
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: const Text('Call'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _LocationQualityBlock(
              customer: c,
              myPosition: _position,
              onSubmitted: () {
                Navigator.pop(ctx);
                _locateAndLoad(force: true);
              },
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Root navigator so the detail screen covers the HomeShell
                  // chrome — the same pattern the customer list uses.
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CustomerDetailScreen(customerId: c.id),
                    ),
                  );
                },
                icon: const Icon(Icons.person_rounded, size: 18),
                label: const Text('View customer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text) => ProEmpty(
        icon: Icons.person_search_rounded,
        title: text,
      );

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 30) return '${d.inDays} days ago';
    return '${(d.inDays / 30).floor()} months ago';
  }
}

/// One location / freshness note ([ProNote] look, with an optional action).
class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.status});
  final _Status status;

  @override
  Widget build(BuildContext context) {
    final m = status;
    final Color bg;
    if (m.color == AppColors.danger) {
      bg = AppColors.dangerTint;
    } else if (m.color == AppColors.warning) {
      bg = AppColors.warningTint;
    } else {
      bg = AppColors.neutralTint;
    }
    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, m.action != null ? 6 : 14, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(m.icon, size: 18, color: m.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(m.text,
                style: TextStyle(fontSize: 13, height: 1.45, color: m.color)),
          ),
          if (m.action != null)
            TextButton(
              onPressed: () => Geolocator.openAppSettings(),
              child: Text(m.action!),
            ),
        ],
      ),
    );
  }
}

// Location quality for one customer, plus the action that fixes it.
///
/// A visit is only as trustworthy as the pin it is measured against, and only
/// the person standing at the door knows where that is. So the employee sees
/// whether the stored pin has ever been confirmed, how far they are from it
/// right now, and can send their own position as the truth — which goes to an
/// approver rather than silently moving the customer, because moving a pin
/// changes what every past visit was measured against.
class _LocationQualityBlock extends ConsumerStatefulWidget {
  const _LocationQualityBlock({
    required this.customer,
    required this.myPosition,
    required this.onSubmitted,
  });

  final NearbyCustomer customer;
  final Position? myPosition;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<_LocationQualityBlock> createState() =>
      _LocationQualityBlockState();
}

class _LocationQualityBlockState extends ConsumerState<_LocationQualityBlock> {
  bool _busy = false;

  /// Beyond this the employee is too far away for their fix to be evidence of
  /// where the customer is.
  static const _maxCaptureDistanceMeters = 100.0;

  Future<void> _submit() async {
    final pos = widget.myPosition;
    if (pos == null || _busy) return;
    final c = widget.customer;
    final moving = c.hasLocation;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(moving ? 'Correct this location?' : 'Set this location?'),
        content: Text(
          moving
              ? 'Your current position will be sent for approval as the '
                  "customer's real location. It is ${c.distanceLabel} from the "
                  'stored pin.\n\nAccuracy of your fix: ±${pos.accuracy.round()} m.'
              : "Your current position will be saved as this customer's "
                  'location.\n\nAccuracy of your fix: '
                  '±${pos.accuracy.round()} m.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(moving ? 'Send for approval' : 'Save location'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final status =
          await ref.read(nearbyCustomerRepositoryProvider).suggestLocation(
                customerId: c.id,
                latitude: pos.latitude,
                longitude: pos.longitude,
                accuracyMeters: pos.accuracy,
                reason: moving
                    ? 'Captured on site; stored pin was ${c.distanceLabel} away'
                    : 'Captured on site (customer had no location)',
              );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'APPROVED'
              ? 'Location saved for ${c.customerName}.'
              : 'Sent for approval. Thank you.'),
        ),
      );
      widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_message(e))),
      );
    }
  }

  /// Turns the backend's ApiResponse error into something readable.
  String _message(Object e) {
    final s = e.toString();
    if (s.contains('already awaiting approval')) {
      return 'A correction for this customer is already awaiting approval.';
    }
    return 'Could not send the location. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final user = ref.watch(authUserProvider);
    final canSuggest = user?.hasPermission('CUSTOMER_LOCATION_SUGGEST') ?? false;
    final pos = widget.myPosition;

    final Color tone = c.locationVerified
        ? AppColors.success
        : c.locationNeedsCorrection
            ? AppColors.info
            : AppColors.warning;
    final IconData icon = c.locationVerified
        ? Icons.verified_rounded
        : c.locationNeedsCorrection
            ? Icons.hourglass_top_rounded
            : Icons.help_outline_rounded;

    // Only a fix taken near the customer is evidence of where they are; and a
    // very rough fix would just replace one bad pin with another.
    final tooFar = c.hasLocation && c.distanceMeters > _maxCaptureDistanceMeters;
    final noFix = pos == null;
    final roughFix = pos != null && pos.accuracy > 50;
    final canAct = canSuggest &&
        !noFix &&
        !tooFar &&
        !c.locationNeedsCorrection &&
        !_busy;

    String? blockedReason;
    if (!canSuggest) {
      blockedReason = null; // no permission: show nothing, not an explanation
    } else if (c.locationNeedsCorrection) {
      blockedReason = 'A correction is already awaiting approval.';
    } else if (noFix) {
      blockedReason = 'Waiting for your GPS position.';
    } else if (tooFar) {
      blockedReason =
          'Stand at the customer to confirm — you are ${c.distanceLabel} away.';
    } else if (roughFix) {
      blockedReason =
          'Your GPS is currently ±${pos.accuracy.round()} m; move outside for a better fix if you can.';
    }

    final Color tint = c.locationVerified
        ? AppColors.successTint
        : c.locationNeedsCorrection
            ? AppColors.infoTint
            : AppColors.warningTint;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.locationQualityLabel,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: tone),
                ),
              ),
              if (pos != null)
                Text('±${pos.accuracy.round()} m',
                    style: AppText.caption.merge(AppText.number)),
            ],
          ),
          if (canSuggest) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: AppColors.surface),
                onPressed: canAct ? _submit : null,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: Text(!c.hasLocation
                    ? 'Set location from where I am'
                    : c.locationVerified
                        ? 'Re-capture location from where I am'
                        : 'Confirm location from where I am'),
              ),
            ),
          ],
          if (blockedReason != null) ...[
            const SizedBox(height: 6),
            Text(blockedReason, style: AppText.caption),
          ],
        ],
      ),
    );
  }
}

class _Cluster {
  _Cluster(this.centre, this.members);
  final LatLng centre;
  final List<NearbyCustomer> members;
}

class _Status {
  _Status(this.text, this.icon, this.color, this.action);
  final String text;
  final IconData icon;
  final Color color;
  final String? action;
}
