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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../attendance/location_tracker.dart';
import 'customer_detail_screen.dart';
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
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Hands the destination to the platform's maps app. Only the coordinates are
  /// passed — never the customer's name, phone number or account details, which
  /// have no business leaving the app.
  Future<void> _navigateTo(NearbyCustomer c) async {
    if (!c.hasLocation) return;
    final lat = c.latitude!, lng = c.longitude!;
    final candidates = <Uri>[
      Uri.parse('google.navigation:q=$lat,$lng&mode=d'), // Android turn-by-turn
      Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=d'), // iOS
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
    ];
    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {
        // Try the next scheme.
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
    final uri = Uri(scheme: 'tel', path: number.trim());
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _toast('Could not start the call.');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final customers = _visible;
    final me = _position == null
        ? null
        : LatLng(_position!.latitude, _position!.longitude);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Nearby Customers'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _locateAndLoad(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _locateAndLoad(force: true),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _statusStrip(),
            _controls(),
            if (!_config.nearbyCustomersEnabled)
              _message('Nearby Customers is not enabled for your company.')
            else ...[
              _map(me, customers),
              _legend(),
              _listHeader(customers.length),
              if (_loading && _result == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (customers.isEmpty)
                _message(_emptyMessage())
              else
                ...customers.map(_customerTile),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
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

  /// Location / freshness / accuracy banner. Everything the employee needs to
  /// judge how much to trust what they're looking at.
  Widget _statusStrip() {
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
    if (messages.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final m in messages)
          Container(
            width: double.infinity,
            color: m.color.withOpacity(0.10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(m.icon, size: 18, color: m.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(m.text,
                      style: TextStyle(fontSize: 12.5, color: m.color)),
                ),
                if (m.action != null)
                  TextButton(
                    onPressed: () => Geolocator.openAppSettings(),
                    child: Text(m.action!, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final metres in _config.radiusOptions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(metres < 1000
                          ? '$metres m'
                          : '${(metres / 1000).toStringAsFixed(0)} km'),
                      selected: _radius == metres,
                      onSelected: (_) {
                        setState(() => _radius = metres);
                        if (_position != null) {
                          _load(LatLng(
                              _position!.latitude, _position!.longitude));
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final c in CustomerCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(c.label),
                    selected: _categories.contains(c),
                    avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _categories.add(c);
                      } else {
                        _categories.remove(c);
                      }
                    }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search name, ID, mobile or village',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                    ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _map(LatLng? me, List<NearbyCustomer> customers) {
    final centre = me ??
        (customers.isNotEmpty && customers.first.hasLocation
            ? LatLng(customers.first.latitude!, customers.first.longitude!)
            : const LatLng(20.5937, 78.9629)); // India, as a last resort

    return SizedBox(
      height: 320,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
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
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          for (final c in CustomerCategory.values)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration:
                      BoxDecoration(color: c.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(c.label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted)),
              ],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              const Text('You',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listHeader(int count) {
    final result = _result;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Text('$count customer${count == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
          const Spacer(),
          if (result != null)
            Text(
              result.fromCache
                  ? 'Cached ${_time(result.generatedAt)}'
                  : 'Updated ${_time(result.generatedAt)}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
        ],
      ),
    );
  }

  Widget _customerTile(NearbyCustomer c) {
    return InkWell(
      onTap: () => _showCustomer(c),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                  color: c.category.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(c.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink)),
                      ),
                      Text(c.distanceLabel,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [c.customerCode, c.placeLabel]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  if (c.outstandingAmount != null || c.overdueDays != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [
                          if (c.outstandingAmount != null)
                            'Outstanding ₹${c.outstandingAmount!.toStringAsFixed(0)}',
                          if (c.overdueDays != null)
                            '${c.overdueDays} days overdue',
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.category.color),
                      ),
                    ),
                  if (c.lastVisitedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        c.visitedRecentlyByColleague
                            ? 'A colleague visited ${_ago(c.lastVisitedAt!)}'
                            : 'Last visit ${_ago(c.lastVisitedAt!)}',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomer(NearbyCustomer c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, 20 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: c.category.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.customerName,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                ),
                Text(c.distanceLabel,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                c.customerCode,
                c.category.label,
                c.placeLabel,
              ].where((s) => s != null && s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            if (c.outstandingAmount != null || c.overdueDays != null) ...[
              const SizedBox(height: 10),
              Text(
                [
                  if (c.outstandingAmount != null)
                    'Outstanding ₹${c.outstandingAmount!.toStringAsFixed(0)}',
                  if (c.overdueDays != null) '${c.overdueDays} days overdue',
                ].join('   ·   '),
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: c.category.color),
              ),
            ],
            if (c.lastVisitedByMeAt != null) ...[
              const SizedBox(height: 8),
              Text('You last visited ${_ago(c.lastVisitedByMeAt!)}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.muted)),
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
                const SizedBox(width: 8),
                // Only rendered when the server sent a number — i.e. when the
                // employee is permitted to see contact details at all.
                if (c.mobileNumber != null && c.mobileNumber!.isNotEmpty)
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
            ),
            const SizedBox(height: 8),
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

  Widget _message(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Icon(Icons.person_search_rounded,
                size: 40, color: AppColors.muted.withOpacity(0.6)),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.muted)),
          ],
        ),
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
