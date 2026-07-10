// ─────────────────────────────────────────────────────────────────────────────
//  MIS · Branch Locator (route /mis/locations). Every branch in the caller's
//  scope on an OpenStreetMap map; searchable; tap a pin to open it in Google
//  Maps. Ports LocationsScreen.tsx (Leaflet → flutter_map).
//
//  Uses OpenStreetMap raster tiles — no API key or Google Play Services needed,
//  so it renders on any device/emulator. Tapping a pin still opens the branch
//  in the Google Maps app via a URL.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_models.dart';
import 'mis_repository.dart';
import 'mis_widgets.dart';

class MisLocationsScreen extends ConsumerStatefulWidget {
  const MisLocationsScreen({super.key});

  @override
  ConsumerState<MisLocationsScreen> createState() => _MisLocationsScreenState();
}

class _MisLocationsScreenState extends ConsumerState<MisLocationsScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();
  String _query = '';
  String _fittedSig = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openInMaps(BranchLocationRow b) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${b.lat},${b.lng}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _fit(List<BranchLocationRow> rows) {
    if (rows.isEmpty) return;
    final sig = '${rows.length}:${rows.first.branchId}:${rows.last.branchId}';
    if (sig == _fittedSig) return;
    _fittedSig = sig;
    final points = [for (final b in rows) LatLng(b.lat, b.lng)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 12);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(48),
          ),
        );
      }
    });
  }

  void _showBranch(BranchLocationRow b) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(b.branch,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [b.area, b.region].where((s) => s != null && s.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _openInMaps(b);
                },
                icon: const Icon(Icons.map_rounded, size: 18),
                label: const Text('Open in Google Maps'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(misBranchLocationsProvider);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Branch Locator')),
      body: async.when(
        loading: () => const AppLoadingBlock(height: 300),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: AppErrorPanel(
            message: e.toString(),
            onRetry: () => ref.invalidate(misBranchLocationsProvider),
          ),
        ),
        data: (all) {
          final withCoords = all.where((b) => b.hasCoords).toList();
          final q = _query.trim().toLowerCase();
          final rows = q.isEmpty
              ? withCoords
              : withCoords
                  .where((b) => '${b.branch} ${b.area ?? ''} ${b.region ?? ''}'
                      .toLowerCase()
                      .contains(q))
                  .toList();
          _fit(rows);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search branch / area / region…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: MisInlineEmpty('No mapped branches in your scope.'),
                      )
                    : ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: LatLng(rows.first.lat, rows.first.lng),
                            initialZoom: 6,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.nava360.app',
                            ),
                            MarkerLayer(
                              markers: [
                                for (final b in rows)
                                  Marker(
                                    point: LatLng(b.lat, b.lng),
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.topCenter,
                                    child: GestureDetector(
                                      onTap: () => _showBranch(b),
                                      child: Icon(
                                        Icons.location_on,
                                        color: AppColors.primary,
                                        size: 34,
                                        shadows: [
                                          Shadow(
                                              color: Colors.black26,
                                              blurRadius: 4,
                                              offset: Offset(0, 2)),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
