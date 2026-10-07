import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/pro_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'team_tracking_repository.dart';

/// Shows a team member's GPS tracking for today plus an on-demand "live location"
/// request. The map itself opens in Google Maps (the app has no embedded map).
class TeamMemberTrackingScreen extends ConsumerStatefulWidget {
  const TeamMemberTrackingScreen({
    super.key,
    required this.employeeId,
    required this.name,
  });

  final int employeeId;
  final String name;

  @override
  ConsumerState<TeamMemberTrackingScreen> createState() =>
      _TeamMemberTrackingScreenState();
}

class _TeamMemberTrackingScreenState
    extends ConsumerState<TeamMemberTrackingScreen> {
  List<TrackPing>? _pings;
  bool _loading = true;
  String? _error;

  LiveLocation? _live;
  bool _liveLoading = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pings = await ref
          .read(teamTrackingRepositoryProvider)
          .memberDay(widget.employeeId, DateTime.now());
      if (!mounted) return;
      setState(() {
        _pings = pings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load tracking. Pull to retry.';
        _loading = false;
      });
    }
  }

  Future<void> _requestLive() async {
    _poll?.cancel();
    setState(() => _liveLoading = true);
    final repo = ref.read(teamTrackingRepositoryProvider);
    try {
      final l = await repo.requestLive(widget.employeeId);
      if (!mounted) return;
      setState(() => _live = l);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liveLoading = false;
        _live = null;
      });
      _toast('Could not request live location');
      return;
    }
    final startedAt = DateTime.now();
    _poll = Timer.periodic(const Duration(seconds: 3), (t) async {
      try {
        final l = await repo.getLive(widget.employeeId);
        if (!mounted) return;
        setState(() => _live = l);
        final timedOut =
            DateTime.now().difference(startedAt) > const Duration(seconds: 32);
        if (l.responded || !l.pending || timedOut) {
          t.cancel();
          if (mounted) setState(() => _liveLoading = false);
        }
      } catch (_) {
        // transient — keep polling until timeout
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _toast('Could not open Google Maps');
  }

  void _openLiveOnMap() {
    final l = _live;
    if (l?.latitude == null || l?.longitude == null) return;
    _open(Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${l!.latitude},${l.longitude}'));
  }

  void _openRouteOnMap() {
    final pings = _pings ?? const [];
    if (pings.length < 2) return;
    final pts = _downsample(pings, 10); // origin + ≤8 waypoints + destination
    final origin = pts.first;
    final dest = pts.last;
    final mid = pts.sublist(1, pts.length - 1);
    final waypoints =
        mid.map((p) => '${p.latitude},${p.longitude}').join('|');
    final url = StringBuffer('https://www.google.com/maps/dir/?api=1')
      ..write('&origin=${origin.latitude},${origin.longitude}')
      ..write('&destination=${dest.latitude},${dest.longitude}')
      ..write('&travelmode=driving');
    if (waypoints.isNotEmpty) url.write('&waypoints=$waypoints');
    _open(Uri.parse(url.toString()));
  }

  @override
  Widget build(BuildContext context) {
    final pings = _pings ?? const <TrackPing>[];
    final ready = !_loading && _error == null;
    final last = pings.isNotEmpty ? pings.last : null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Tracking')),
      body: ProPage(
        onRefresh: _load,
        hero: ProHero(
          kicker: 'Today\'s tracking',
          title: widget.name,
          children: [
            ProHeroStats(stats: [
              ProStat(
                label: 'Pings',
                value: ready ? '${pings.length}' : '—',
                dot: AppColors.live,
              ),
              ProStat(
                label: 'Distance',
                value: ready ? '${_totalKm(pings).toStringAsFixed(2)} km' : '—',
                dot: const Color(0xFF7FC8D8),
              ),
              ProStat(
                label: 'Last seen',
                value: ready && last != null ? _hhmm(last.recordedAt) : '—',
                dot: Colors.white54,
              ),
            ]),
          ],
        ),
        children: [
          _liveCard(),
          if (_loading)
            const AppLoadingBlock()
          else if (_error != null)
            AppErrorPanel(message: _error!, onRetry: _load)
          else
            _summaryCard(),
        ],
      ),
    );
  }

  // ── Live ──────────────────────────────────────────────────────────────────
  Widget _liveCard() {
    final l = _live;
    final hasFix = l?.latitude != null && l?.longitude != null;
    final tone = l == null
        ? AppColors.muted
        : (l.state == 'ON' && hasFix)
            ? AppColors.success
            : l.pending
                ? AppColors.primary
                : AppColors.warning;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProSectionHeader(
            title: 'Live location',
            trailing: (_liveLoading || (l?.pending ?? false))
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          if (l != null) ...[
            const SizedBox(height: 8),
            Text(
              l.message,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: tone,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (hasFix) ...[
              const SizedBox(height: 4),
              Text(
                '${l.latitude!.toStringAsFixed(5)}, ${l.longitude!.toStringAsFixed(5)}',
                style: AppText.caption.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _liveLoading ? null : _requestLive,
                  icon: const Icon(Icons.gps_fixed, size: 18),
                  label: Text(_liveLoading ? 'Locating…' : 'Get live location'),
                ),
              ),
              if (hasFix) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _openLiveOnMap,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Map'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Today summary ───────────────────────────────────────────────────────────
  Widget _summaryCard() {
    final pings = _pings ?? const [];
    final first = pings.isNotEmpty ? pings.first : null;
    final last = pings.isNotEmpty ? pings.last : null;
    final km = _totalKm(pings);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProSectionHeader(title: 'Today'),
          const SizedBox(height: 6),
          ProKeyValue(rows: [
            MapEntry('Pings', '${pings.length}'),
            MapEntry('Distance', '${km.toStringAsFixed(2)} km'),
            MapEntry('First seen', first == null ? '—' : _hhmm(first.recordedAt)),
            MapEntry('Last seen', last == null ? '—' : _hhmm(last.recordedAt)),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: pings.length < 2 ? null : _openRouteOnMap,
            icon: const Icon(Icons.route_outlined, size: 18),
            label: Text(pings.length < 2
                ? 'No route to show today'
                : 'Open today\'s route in Google Maps'),
          ),
        ],
      ),
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────────
  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _hhmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

  static List<TrackPing> _downsample(List<TrackPing> pts, int max) {
    if (pts.length <= max) return pts;
    final step = (pts.length - 1) / (max - 1);
    return List.generate(max, (i) => pts[(i * step).round()]);
  }

  static double _totalKm(List<TrackPing> pts) {
    double km = 0;
    for (var i = 1; i < pts.length; i++) {
      km += _haversineKm(pts[i - 1], pts[i]);
    }
    return km;
  }

  static double _haversineKm(TrackPing a, TrackPing b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) *
            math.sin(dLng / 2) *
            math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude));
    return 2 * r * math.asin(math.min(1, math.sqrt(h)));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
