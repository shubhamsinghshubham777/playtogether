import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/ui/pt_motion.dart';
import 'package:playtogether/ui/pt_theme.dart';

/// Total run: logo in, hold, cross-fade out.
const _kTotal = Duration(milliseconds: 1800);

/// The accent — the logo's spring reaches full overshoot here, and the sound's
/// transient is cut to hit the same instant (`IMPACT` in
/// tool/generate_splash_sound.py). Move one, move the other.
const _kImpact = Duration(milliseconds: 300);

/// The audio player gets this long to open the file before the animation
/// starts without it. Sound and motion are one gesture, so a late start would
/// read as a bug; silence just reads as a quiet app.
const _kPreloadBudget = Duration(milliseconds: 450);

const _kSfx = 'asset:///assets/sfx/splash.wav';

/// Underdamped spring settle: overshoots once by ~17%, undershoots a hair,
/// done. [PTMotion.arrive]'s easeOutBack is the kit's overshoot curve, but it
/// has to spend its whole interval on a single lean-back — a real spring can
/// take the same time and still feel like it *lands* partway through, which is
/// what lets the visual accent sit on the audio transient.
/// Its first and largest overshoot (~17%) peaks at π/frequency ≈ 0.273 of the
/// interval — that fraction is the beat the ear reads as the hit, and it is
/// what the tile's timing below is solved against.
class _Spring extends Curve {
  const _Spring();

  static const _damping = 6.5;
  static const _frequency = 11.5;

  @override
  double transformInternal(double t) =>
      1 -
      math.exp(-_damping * t) *
          (math.cos(_frequency * t) + _damping / _frequency * math.sin(_frequency * t));
}

const _spring = _Spring();

Interval _beat(int startMs, int endMs, Curve curve) =>
    Interval(startMs / _kTotal.inMilliseconds, endMs / _kTotal.inMilliseconds, curve: curve);

/// The choreography, in milliseconds from t=0.
///
/// Only the tile is timed to the audio: its spring peaks on [_kImpact]
/// (110 + 0.273 × 700 ≈ 300). Everything else trails it as follow-through, so
/// the ear hears one hit and not three. Scale and opacity run on separate
/// intervals on purpose — a spring that faded over its whole travel would
/// still be translucent at the moment it is supposed to land.
final _tile = _beat(110, 810, _spring);
final _tileFade = _beat(110, 400, PTMotion.enter);
final _glyph = _beat(200, 640, PTMotion.enter);
final _ring = _beat(300, 880, PTMotion.exit);
final _word = _beat(210, 910, _spring);
final _wordFade = _beat(210, 490, PTMotion.enter);

/// The app is built here, still hidden, so its first frame — glass blurs,
/// shader warm-up, the lobby's whole tree — is paid for during the hold
/// instead of on the first frame of the fade, where it stalls the raster
/// thread and turns the cross-fade into a cut.
final _prewarm = 950 / _kTotal.inMilliseconds;
final _exit = _beat(1240, _kTotal.inMilliseconds, PTMotion.emphasized);

/// Cold-start splash: holds the app back for one beat, plays the logo sting,
/// then cross-fades so the lobby's own entrance choreography plays into the
/// gap rather than behind an opaque cover.
///
/// It is an overlay in `MaterialApp.builder`, not a route — the router,
/// redirects and the deep-link handler in main.dart all keep running
/// underneath, so an invite link that arrives during the splash still lands.
class PTSplash extends StatefulWidget {
  const PTSplash({super.key, required this.child});

  final Widget child;

  @override
  State<PTSplash> createState() => _PTSplashState();
}

class _PTSplashState extends State<PTSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: _kTotal)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) setState(() => _finished = true);
    });

  Player? _sound;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    // Opening the file first is what buys the sync: media_kit's own start
    // latency lands before t=0 instead of inside the animation.
    final player = await _preload().timeout(_kPreloadBudget, onTimeout: () => null);
    if (!mounted) {
      unawaited(player?.dispose());
      return;
    }
    _sound = player;
    unawaited(player?.play());
    if (reducedMotion(context)) {
      // Decorative motion renders its end state; the sting still plays, and
      // the hold gives it somewhere to land before the hand-off.
      _controller.value = _exit.begin;
      Timer(_kImpact, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  Future<Player?> _preload() async {
    final player = Player();
    try {
      await player.setVolume(75);
      await player.open(Media(_kSfx), play: false);
      return player;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading the splash sound');
      unawaited(player.dispose());
      return null;
    }
  }

  @override
  void dispose() {
    // The splash outlives the 1.30 s sting, so this never clips a tail.
    unawaited(_sound?.dispose());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;
    return Stack(
      fit: .expand,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) =>
              _controller.value >= _prewarm ? widget.child : const SizedBox.shrink(),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final leaving = _exit.transform(_controller.value);
            if (leaving >= 1) return const SizedBox.shrink();
            return Opacity(
              opacity: 1 - leaving,
              child: _Stage(_controller, exit: leaving),
            );
          },
        ),
      ],
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage(this.animation, {required this.exit});

  final Animation<double> animation;
  final double exit;

  @override
  Widget build(BuildContext context) {
    final t = animation.value;
    // `MaterialApp.builder` sits above every Scaffold, so there is no ancestor
    // text style here — without this the wordmark paints with the framework's
    // yellow "unstyled text" underline.
    return DefaultTextStyle(
      style: PTText.body,
      child: DecoratedBox(
        // A radial wash rather than the lobby's AmbientBackground: its blurred
        // blobs compile shaders on the very first frame drawn, which is exactly
        // the frame this screen cannot afford to drop.
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.9,
            colors: [Color(0xFF1A1130), PTColors.screenBg, PTColors.canvas],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Center(
          child: Transform.scale(
            // Drifts forward as it leaves, so the hand-off reads as passing
            // through the logo into the app.
            scale: 1 + 0.06 * exit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: FittedBox(
                fit: .scaleDown,
                child: Row(
                  mainAxisSize: .min,
                  children: [_Tile(t), const SizedBox(width: 24), _Wordmark(t)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.t);

  static const _size = 104.0;

  final double t;

  @override
  Widget build(BuildContext context) {
    final spring = _tile.transform(t);
    final fade = _tileFade.transform(t).clamp(0.0, 1.0);
    final glyph = _glyph.transform(t).clamp(0.0, 1.0);
    final ring = _ring.transform(t);
    return SizedBox.square(
      dimension: _size,
      child: Stack(
        alignment: .center,
        clipBehavior: Clip.none,
        children: [
          // One pulse leaving the tile on the impact, gone before the wordmark
          // settles. OverflowBox because a non-positioned Stack child is
          // constrained to the Stack's size — the ring has to outgrow it.
          if (ring > 0 && ring < 1)
            OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Opacity(
                opacity: (1 - ring) * 0.5,
                child: Container(
                  width: _size * (0.9 + ring * 0.8),
                  height: _size * (0.9 + ring * 0.8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_size * 0.32 * (1 + ring)),
                    border: Border.all(
                      color: PTColors.gradientEnd.withValues(alpha: 0.55),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          Opacity(
            opacity: fade,
            child: Transform.scale(
              scale: 0.5 + 0.5 * spring,
              // Same geometry as the lobby wordmark (_Wordmark in
              // lobby_screen.dart) so the splash resolves into the real logo.
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  gradient: PTColors.brandGradient,
                  borderRadius: BorderRadius.circular(_size * 0.32),
                  boxShadow: [
                    BoxShadow(
                      color: PTColors.primary.withValues(alpha: 0.45 * fade),
                      blurRadius: 46,
                      spreadRadius: 4,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Center(
                  child: Transform.scale(
                    scale: 0.55 + 0.45 * glyph,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: _size * 0.55,
                      color: Colors.white.withValues(alpha: glyph),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark(this.t);

  final double t;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _wordFade.transform(t).clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.62 + 0.38 * _word.transform(t),
        // Anchored to the tile it grows out of, rather than to its own middle,
        // so the two read as one object springing in.
        alignment: .centerLeft,
        child: const Text(
          'PlayTogether',
          style: TextStyle(
            fontFamily: PTFonts.display,
            fontSize: 42,
            fontWeight: .w700,
            letterSpacing: -0.6,
            color: Colors.white,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
