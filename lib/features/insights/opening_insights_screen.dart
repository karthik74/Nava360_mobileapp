import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'insights_models.dart';
import 'insights_repository.dart';
import 'opening_insights_trigger.dart';

/// The intro's guide: a transparent, looping animated WebP (480×854, 15 fps).
const kOpeningInsightsCharacter =
    AssetImage('assets/insights/nava360_character.webp');

/// Warms the image cache with the character's first frame so the intro can
/// start its timeline on its very first frame. Safe to call repeatedly.
void precacheOpeningInsightsCharacter(BuildContext context) {
  precacheImage(kOpeningInsightsCharacter, context, onError: (_, __) {});
}

// ── Timeline (seconds) — mirrors render() in the approved HTML prototype ────
const double _kDuration = 10; // reveal ends; only the character keeps looping
const double _kArrivalAt = .05, _kArrivalLen = .75; // character + orbit in
const double _kZoomAt = 6.9, _kZoomLen = .7; // 1.22× close-up pulls back
const double _kLeftHeadAt = 1.05,
    _kRightHeadAt = 2.65,
    _kTeaserLen = .6; // headings, left first
const double _kCtaAt = 5.55, _kCtaLen = .75; // button (enabled once fully in)
const List<double> _kRowAt = [7.35, 7.55, 7.75]; // card pairs
const double _kCardLen = .6; // card rise
const double _kCountDelay = .1, _kCountLen = .55; // count-up after rise starts
const Duration _kAffirmHold = Duration(milliseconds: 1100); // feedback beat

// ── Palette ─────────────────────────────────────────────────────────────────
const _cBg0 = Color(0xFFFFFDF7);
const _cBg1 = Color(0xFFF5F3E9);
const _cBg2 = Color(0xFFE9EAD7);
const _cTeaser = Color(0xFF5B6F34);
const _cLabel = Color(0xFF63723B);
const _cValue = Color(0xFF253018);
const _cMeta = Color(0xFF78816E);
const _cCard = Color(0xFFFFFEFA);
const _cCardBorder = Color(0xFFD8DDC8);
const _cCardShadow = Color(0x1C4A5938);
const _cOrbit = Color(0xFFECF0DD);
const _cOrbitBorder = Color(0xFFDCE3C6);
const _cCta = Color(0xFF667C31);
const _cCtaPressed = Color(0xFF526D2B);
const _cCtaShadow = Color(0x40485D2E);
const _cFeedback = Color(0xFF627A36);
const _cCharShadow = Color(0x40525943);

/// Phone aspect the layout was designed on (9 : 19.5). All geometry below is
/// in `u` = 1 % of that stage's width (the prototype's `cqw`).
const double _kStageAspect = 19.5 / 9;

double _clamp01(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);
double _phase(double t, double start, double length) =>
    _clamp01((t - start) / length);
double _ease(double x) => 1 - math.pow(1 - x, 3).toDouble(); // easeOutCubic

/// Full-screen "opening insights" intro. The guide arrives, the FTD and MTD
/// headings appear beside her, the "i'll improve and work hard today" button
/// rises, then she pulls back and six cards rise and count up around her:
/// Disbursement / FTOD / PTP for yesterday (FTD, left) and this month (MTD, right).
///
/// It never leaves on its own: the user taps the button (or Back), sees a
/// short encouragement, and goes on — popping back to the screen underneath
/// (resume trigger) or to /home (login / cold start). A notification tap ends
/// it at once and opens that route. Slow or failed data never blocks the
/// button; the cards show "—" until numbers arrive.
class OpeningInsightsScreen extends ConsumerStatefulWidget {
  const OpeningInsightsScreen({
    super.key,
    this.onFinish,
    this.now,
    this.characterWait = const Duration(milliseconds: 800),
  });

  /// Replaces the default navigation when the intro ends. Receives the route
  /// a notification tap asked for (null for a normal finish).
  final void Function(String? nextRoute)? onFinish;

  /// Clock override for tests (the FTD date fallback); defaults to now.
  final DateTime Function()? now;

  /// Longest wait for the character's first frame before the timeline starts
  /// anyway. [Duration.zero] starts immediately (tests).
  final Duration characterWait;

  @override
  ConsumerState<OpeningInsightsScreen> createState() =>
      _OpeningInsightsScreenState();
}

class _OpeningInsightsScreenState extends ConsumerState<OpeningInsightsScreen>
    with TickerProviderStateMixin {
  late final AnimationController _timeline;
  late final AnimationController _lateCount; // numbers that arrive late
  late final AnimationController _outro;

  OpeningInsightsTrigger? _trigger;
  ImageStream? _charStream;
  ImageStreamListener? _charListener;
  Timer? _charTimeout;
  Timer? _affirmTimer;

  OpeningInsights? _data;
  double _dataAt = 0; // timeline second the numbers arrived
  bool _mounted = false; // past the first didChangeDependencies
  bool _waiting = false; // waiting for the character's first frame
  bool _began = false; // timeline started
  bool _reduceMotion = false;
  bool _pressed = false;
  bool _affirmed = false;
  bool _leaving = false;

  double get _t => _reduceMotion ? _kDuration : _timeline.value * _kDuration;

  double _p(double start, double length) =>
      _reduceMotion ? 1 : _ease(_phase(_t, start, length));

  bool get _ctaReady => _p(_kCtaAt, _kCtaLen) >= 1;

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_kDuration * 1000).round()),
    );
    _lateCount = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_kCountLen * 1000).round()),
    );
    _outro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _trigger = ref.read(openingInsightsTriggerProvider);
    _trigger?.register(_interrupt);

    // Keeps the autoDispose provider alive for as long as the intro is up.
    final sub = ref.listenManual<AsyncValue<OpeningInsights>>(
      openingInsightsProvider,
      (_, next) => _onLoad(next),
    );
    _onLoad(sub.read());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mounted = true;
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_waiting || _began) return;
    if (_reduceMotion) {
      // Everything in its final state at once (the character still plays).
      _began = true;
      _timeline.value = 1;
    } else {
      _awaitCharacter();
    }
  }

  /// Like the prototype waiting for its video's `playing` event: t = 0 is the
  /// moment the character's first frame is ready (at most [characterWait]).
  void _awaitCharacter() {
    _waiting = true;
    final wait = widget.characterWait;
    if (wait <= Duration.zero) {
      _begin();
      return;
    }
    _charTimeout = Timer(wait, _begin);
    _charListener = ImageStreamListener(
      (info, _) {
        info.dispose();
        _begin();
      },
      onError: (_, __) => _begin(),
    );
    final stream = kOpeningInsightsCharacter
        .resolve(createLocalImageConfiguration(context));
    // Assign before listening: a cached first frame calls back synchronously,
    // and _begin must be able to detach this listener right away.
    _charStream = stream;
    stream.addListener(_charListener!);
  }

  void _stopWaiting() {
    _charTimeout?.cancel();
    final l = _charListener;
    if (l != null) _charStream?.removeListener(l);
    _charListener = null;
    _charStream = null;
  }

  void _begin() {
    _stopWaiting();
    if (_began || _leaving || !mounted) return;
    _began = true;
    _timeline.forward();
  }

  @override
  void dispose() {
    _trigger?.unregister(_interrupt);
    _stopWaiting();
    _affirmTimer?.cancel();
    _timeline.dispose();
    _lateCount.dispose();
    _outro.dispose();
    super.dispose();
  }

  void _onLoad(AsyncValue<OpeningInsights> v) {
    // Errors keep the "—" placeholders; nothing ever waits on the data.
    if (_leaving || _data != null || v is! AsyncData<OpeningInsights>) return;
    void apply() {
      _data = v.value;
      _dataAt = _began ? _t : 0;
      // Cards already counting: fill them with their own short count-up.
      if (!_reduceMotion && _dataAt > _kRowAt.first + _kCountDelay) {
        _lateCount.forward(from: 0);
      }
    }

    // Already cached when the screen mounts → no setState inside initState.
    _mounted ? setState(apply) : apply();
  }

  /// A notification tap while the intro is up: leave now, then open [route].
  void _interrupt(String route) => _leave(route);

  void _affirm() {
    if (_affirmed || _leaving) return;
    setState(() {
      _affirmed = true;
      _pressed = true;
    });
    HapticFeedback.mediumImpact().ignore(); // never let haptics fail the tap
    _affirmTimer = Timer(_kAffirmHold, _leave);
  }

  /// Back behaves like the button once it is available; before that it simply
  /// leaves — the intro never traps the user.
  void _onBack() {
    if (_affirmed || _leaving) return;
    _ctaReady ? _affirm() : _leave();
  }

  Future<void> _leave([String? nextRoute]) async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _stopWaiting();
    _affirmTimer?.cancel();
    _trigger?.unregister(_interrupt);
    _timeline.stop();
    // A soft fade-out before handing over (skipped for a notification tap,
    // which should land immediately, and when motion is reduced).
    if (nextRoute == null && !_reduceMotion) {
      await _outro.forward();
    }
    if (!mounted) return;

    final cb = widget.onFinish;
    if (cb != null) {
      cb(nextRoute);
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (router.canPop()) {
      router.pop(); // resume trigger: back to where the user was
    } else {
      router.go('/home'); // login / cold start
    }
    if (nextRoute != null) {
      SchedulerBinding.instance.endOfFrame.then((_) => router.push(nextRoute));
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _cBg2,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: Scaffold(
          backgroundColor: _cBg2,
          body: FadeTransition(
            opacity: ReverseAnimation(_outro),
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth, h = box.maxHeight;
              // Fit the 9:19.5 stage inside the screen, centred.
              final u = math.min(w / 100, h / (100 * _kStageAspect));
              final stageW = 100 * u, stageH = 100 * _kStageAspect * u;
              return DecoratedBox(
                decoration: BoxDecoration(gradient: _background(w, h)),
                child: Stack(
                  children: [
                    Positioned(
                      left: (w - stageW) / 2,
                      top: (h - stageH) / 2,
                      width: stageW,
                      height: stageH,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_timeline, _lateCount]),
                        builder: (context, _) => _stage(u),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  /// `radial-gradient(circle at 52% 40%, #fffdf7 0%, #f5f3e9 55%, #e9ead7)`
  /// — a circle reaching the farthest corner.
  static Gradient _background(double w, double h) {
    const cx = .52, cy = .40;
    final far = math.sqrt(math.pow(math.max(cx, 1 - cx) * w, 2) +
        math.pow(math.max(cy, 1 - cy) * h, 2));
    final shortest = math.max(1.0, math.min(w, h));
    return RadialGradient(
      center: const Alignment(cx * 2 - 1, cy * 2 - 1),
      radius: far / shortest,
      colors: const [_cBg0, _cBg1, _cBg2],
      stops: const [0, .55, 1],
    );
  }

  Widget _stage(double u) {
    final t = _t;
    final arrival =
        _reduceMotion ? 1.0 : _ease(_phase(t, _kArrivalAt, _kArrivalLen));
    final zoom = _reduceMotion ? 1.0 : _ease(_phase(t, _kZoomAt, _kZoomLen));
    final ctaP = _p(_kCtaAt, _kCtaLen);

    final data = _data;
    final now = (widget.now ?? DateTime.now)();
    final ftdDate =
        data?.ftdColumn.date ?? DateTime(now.year, now.month, now.day - 1);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Orbit (z 2).
        Positioned(
          left: 11 * u,
          top: 53 * u,
          width: 78 * u,
          height: 100 * u,
          child: Opacity(
            opacity: arrival * .5,
            child: Transform.scale(
              scale: 1.18 - .18 * zoom,
              child: const DecoratedBox(
                decoration: ShapeDecoration(
                  color: _cOrbit,
                  shape: OvalBorder(side: BorderSide(color: _cOrbitBorder)),
                ),
              ),
            ),
          ),
        ),
        // Character (z 3).
        Positioned(
          left: 17 * u,
          top: 35 * u,
          width: 66 * u,
          height: 112 * u,
          child: IgnorePointer(
            child: Opacity(
              opacity: arrival,
              child: Transform.translate(
                offset: Offset(0, (1 - arrival) * 10 * u),
                child: Transform.scale(
                  scale: (.92 + .08 * arrival) * (1.22 - .22 * zoom),
                  child: _Character(u: u),
                ),
              ),
            ),
          ),
        ),
        // Cards (z 6).
        Positioned(
          left: 4 * u,
          right: 4 * u,
          top: 75 * u,
          child: _cards(u, data),
        ),
        // Headings (z 7).
        // FTD (yesterday) on the left, MTD (this month) on the right.
        _teaser(
          u,
          zoom,
          at: _kLeftHeadAt,
          big: 4.0,
          left: true,
          text: 'FTD · ${insightsShortDate(ftdDate)}',
        ),
        _teaser(u, zoom, at: _kRightHeadAt, big: 5.7, left: false, text: 'MTD'),
        // Button + feedback (z 7).
        Positioned(
          left: 5 * u,
          right: 5 * u,
          top: 179 * u,
          child: Opacity(
            opacity: ctaP,
            child: Transform.translate(
              offset: Offset(0, (1 - ctaP) * 8 * u),
              child: Transform.scale(
                scale: 1.07 - .07 * zoom,
                child: _ctaBlock(u, enabled: ctaP >= 1 && !_leaving),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _teaser(
    double u,
    double zoom, {
    required double at,
    required double big,
    required bool left,
    required String text,
  }) {
    final p = _p(at, _kTeaserLen);
    final size = (big + (2.8 - big) * zoom) * u;
    return Positioned(
      left: left ? 4 * u : null,
      right: left ? null : 4 * u,
      top: (86 - 20 * zoom + (1 - p) * 4) * u,
      width: 29 * u,
      height: size * 1.05,
      child: Opacity(
        opacity: p,
        child: Transform.scale(
          scale: .92 + .08 * p,
          // nowrap: a heading wider than its column overflows evenly.
          child: OverflowBox(
            maxWidth: 60 * u,
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _cTeaser,
                fontSize: size,
                height: 1.05,
                leadingDistribution: TextLeadingDistribution.even,
                fontWeight: FontWeight.w800,
                letterSpacing: -.02 * size,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cards(double u, OpeningInsights? d) {
    final mtd = d?.mtdColumn, ftd = d?.ftdColumn;
    // Rows of (left: FTD, right: MTD) — the same three cards in each column.
    final rows = <(_CardSpec, _CardSpec)>[
      (_disbursement(d, ftd), _disbursement(d, mtd)),
      (_ftod(ftd), _ftod(mtd)),
      (
        _CardSpec('PTP', ftd?.ptp, 'promises due'),
        _CardSpec('PTP', mtd?.ptp, 'promises due'),
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: 2 * u),
          Row(
            children: [
              Expanded(child: _card(u, rows[i].$1, _kRowAt[i])),
              SizedBox(width: 34 * u),
              Expanded(child: _card(u, rows[i].$2, _kRowAt[i])),
            ],
          ),
        ],
      ],
    );
  }

  /// "—" with "not available" once data is in and the feed has no figure
  /// (e.g. yesterday's disbursement); plain "accounts" otherwise.
  static _CardSpec _disbursement(OpeningInsights? d, InsightsColumn? c) {
    final v = c?.disbursement;
    return _CardSpec('Disbursement', v,
        d != null && v == null ? 'not available' : 'accounts');
  }

  /// Accounts still unpaid, with how many fell due behind them.
  static _CardSpec _ftod(InsightsColumn? c) {
    final due = c?.ftodDue;
    return _CardSpec('FTOD', c?.ftod,
        due == null ? 'accounts' : 'of ${insightsCount(due)} due');
  }

  /// Count-up progress (0–1) for a card entering at [at].
  double _count(double at) {
    if (_reduceMotion) return 1;
    final start = at + _kCountDelay;
    if (_dataAt <= start) return _ease(_phase(_t, start, _kCountLen));
    return _ease(_lateCount.value); // numbers arrived after this card counted
  }

  Widget _card(double u, _CardSpec c, double at) {
    final p = _p(at, _kCardLen);
    final v = c.value;
    final shown = (_data == null || v == null)
        ? '—'
        : insightsCount((v * _count(at)).round());
    final labelSize = 2.55 * u, valueSize = 6.8 * u, metaSize = 2.35 * u;
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, (1 - p) * 7 * u),
        child: Transform.scale(
          scale: .94 + .06 * p,
          child: Container(
            height: 27 * u,
            padding: EdgeInsets.all(2.6 * u),
            decoration: BoxDecoration(
              color: _cCard,
              borderRadius: BorderRadius.circular(4 * u),
              border: Border.all(color: _cCardBorder),
              boxShadow: [
                BoxShadow(
                  color: _cCardShadow,
                  offset: Offset(0, 1 * u),
                  blurRadius: 2.5 * u,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.label.toUpperCase(),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    color: _cLabel,
                    fontSize: labelSize,
                    height: 1.1,
                    leadingDistribution: TextLeadingDistribution.even,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .03 * labelSize,
                  ),
                ),
                SizedBox(height: 1.1 * u),
                SizedBox(
                  height: valueSize,
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      shown,
                      maxLines: 1,
                      style: TextStyle(
                        color: _cValue,
                        fontSize: valueSize,
                        height: 1,
                        leadingDistribution: TextLeadingDistribution.even,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.055 * valueSize,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 1 * u),
                Text(
                  c.meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _cMeta,
                    fontSize: metaSize,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ctaBlock(double u, {required bool enabled}) {
    final active = enabled && !_affirmed;
    final down = _pressed || _affirmed;
    final size = 3.35 * u;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          child: GestureDetector(
            key: const ValueKey('opening-insights-cta'),
            behavior: HitTestBehavior.opaque,
            onTapDown: active ? (_) => setState(() => _pressed = true) : null,
            onTapCancel: active ? () => setState(() => _pressed = false) : null,
            onTap: active ? _affirm : null,
            child: Transform.scale(
              scale: down ? .98 : 1,
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(minHeight: 13 * u),
                padding: EdgeInsets.symmetric(
                  vertical: 2 * u,
                  horizontal: 3 * u,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: down ? _cCtaPressed : _cCta,
                  borderRadius: BorderRadius.circular(4 * u),
                  boxShadow: [
                    BoxShadow(
                      color: _cCtaShadow,
                      offset: Offset(0, 2 * u),
                      blurRadius: 5 * u,
                    ),
                  ],
                ),
                child: Text(
                  "i'll improve and work hard today",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size,
                    height: 1.2,
                    leadingDistribution: TextLeadingDistribution.even,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 1.5 * u),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: 4 * u),
          child: Semantics(
            liveRegion: true,
            child: AnimatedOpacity(
              opacity: _affirmed ? 1 : 0,
              duration: _reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              child: Text(
                'You’ve got this. Let’s get started.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _cFeedback,
                  fontSize: 2.7 * u,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardSpec {
  const _CardSpec(this.label, this.value, this.meta);
  final String label;

  /// Null → "—" (no data yet, load failed, or not available).
  final int? value;
  final String meta;
}

/// The animated guide with a soft shadow at her feet (stands in for the
/// prototype's CSS drop-shadow, which Flutter can't apply to an image's alpha
/// cheaply). Laid out in the 66u × 112u character slot.
class _Character extends StatelessWidget {
  const _Character({required this.u});
  final double u;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Feet sit at ~97 % of the image height (image fills the slot height).
        Positioned(
          left: 22 * u,
          width: 22 * u,
          top: 105.5 * u,
          height: 4.5 * u,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(
                Radius.elliptical(11 * u, 2.25 * u),
              ),
              boxShadow: [
                BoxShadow(color: _cCharShadow, blurRadius: 2.8 * u),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: Image(
            image: kOpeningInsightsCharacter,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            semanticLabel: 'Nava360 guide presenting your daily insights',
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
