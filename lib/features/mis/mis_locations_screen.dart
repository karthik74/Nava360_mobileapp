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

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mis_format.dart';
import 'mis_models.dart';
import 'mis_repository.dart';

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
            // Leave room for the floating search (top) and KPI card (bottom).
            padding: const EdgeInsets.fromLTRB(48, 96, 48, 120),
          ),
        );
      }
    });
  }

  void _showBranch(BranchLocationRow b) {
    final sub =
        [b.area, b.region].where((s) => s != null && s.isNotEmpty).join(' · ');
    String orDash(String? v) => v == null || v.isEmpty ? '—' : v;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                ProIconWell(
                    icon: Icons.location_on_rounded,
                    color: AppColors.primary,
                    size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.branch,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.4,
                              color: AppColors.ink)),
                      if (sub.isNotEmpty)
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ProKeyValue(rows: [
              MapEntry('Area', orDash(b.area)),
              MapEntry('Region', orDash(b.region)),
              MapEntry('Coordinates',
                  '${b.lat.toStringAsFixed(4)}, ${b.lng.toStringAsFixed(4)}'),
            ]),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openInMaps(b);
              },
              icon: const Icon(Icons.map_rounded, size: 18),
              label: const Text('Open in Google Maps'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(misBranchLocationsProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Branch locator')),
      body: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: AppLoadingBlock(height: 300),
        ),
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

          int distinct(String? Function(BranchLocationRow) f) => rows
              .map(f)
              .where((s) => s != null && s.isNotEmpty)
              .toSet()
              .length;

          return Stack(
            children: [
              Positioned.fill(
                child: rows.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.fromLTRB(16, 84, 16, 16),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ProEmpty(
                            icon: Icons.location_off_outlined,
                            title: 'Nothing on the map',
                            message: 'No mapped branches in your scope.',
                          ),
                        ),
                      )
                    : FlutterMap(
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
                                    child: const _BranchPin(),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
              // Floating search over the map.
              Positioned(
                left: 16,
                right: 16,
                top: 12,
                child: ProSearchField(
                  raised: true,
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  hint: 'Search branch / area / region…',
                  onClear: () => setState(() => _query = ''),
                ),
              ),
              // Scope figures for the branches currently on the map.
              if (rows.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16 + bottomInset,
                  child: ProKpiStrip(cells: [
                    ProKpi(
                      value: misNum(rows.length),
                      label: q.isEmpty
                          ? 'Branches'
                          : 'of ${misNum(withCoords.length)} branches',
                    ),
                    ProKpi(value: misNum(distinct((b) => b.area)), label: 'Areas'),
                    ProKpi(
                        value: misNum(distinct((b) => b.region)),
                        label: 'Regions'),
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Brand map pin with a white ring.
class _BranchPin extends StatelessWidget {
  const _BranchPin();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(
          Icons.location_on,
          color: AppColors.primary,
          size: 36,
          shadows: const [
            Shadow(color: Color(0x400B1D21), blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        Positioned(
          top: 8,
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}
