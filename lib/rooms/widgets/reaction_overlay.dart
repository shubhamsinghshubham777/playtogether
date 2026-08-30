import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lottie/lottie.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/rooms/reaction_cdn.dart';
import 'package:synctogether/rooms/reactions.dart';
import 'package:synctogether/sync/sync_events.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

class ReactionAssets {
  ReactionAssets({ReactionCdn? cdn}) : _cdn = cdn ?? ReactionCdn.instance;

  final ReactionCdn _cdn;
  final _compositions = <String, LottieComposition>{};
  final _resolving = <String>{};
  Future<void>? _preloading;

  /// Null means "render the glyph for now". The overlay resolves compositions
  /// per frame, so anything that lands later upgrades in place rather than
  /// staying flat for the particle's whole life.
  LottieComposition? of(PTReaction reaction) {
    final ready = _compositions[reaction.codepoint];
    if (ready != null) return ready;
    if (!reaction.isBundled) unawaited(_resolveExtended(reaction));
    return null;
  }

  Future<void> preload() => _preloading ??= _load();

  /// Only the bundled set is preloaded. The extended set is fetched on demand:
  /// pulling two dozen animations off the network on room entry would spend
  /// bandwidth the video wants, for emoji nobody may send.
  Future<void> _load() async {
    for (final reaction in kReactions) {
      try {
        _compositions[reaction.codepoint] = await AssetLottie(
          reaction.asset,
          backgroundLoading: true,
        ).load();
      } catch (e, s) {
        reportNonFatal(e, s, during: 'preloading the ${reaction.codepoint} reaction animation');
      }
    }
  }

  Future<void> warmExtended(Iterable<PTReaction> reactions) async {
    for (final reaction in reactions) {
      if (reaction.isBundled || _compositions.containsKey(reaction.codepoint)) continue;
      await _resolveExtended(reaction);
    }
  }

  Future<void> _resolveExtended(PTReaction reaction) async {
    if (_compositions.containsKey(reaction.codepoint)) return;
    if (!_resolving.add(reaction.codepoint)) return;
    try {
      final bytes = await _cdn.load(reaction);
      if (bytes == null) return;
      _compositions[reaction.codepoint] = await LottieComposition.fromBytes(
        Uint8List.fromList(bytes),
      );
    } catch (e, s) {
      reportNonFatal(e, s, during: 'decoding the ${reaction.codepoint} reaction animation');
    } finally {
      _resolving.remove(reaction.codepoint);
    }
  }
}

class ReactionOverlay extends StatefulWidget {
  const ReactionOverlay({
    super.key,
    required this.reactions,
    required this.assets,
    this.spawnBottom = 24,
    this.compact = false,
  });

  final Stream<ReactionEvent> reactions;
  final ReactionAssets assets;
  final double spawnBottom;
  final bool compact;

  @override
  State<ReactionOverlay> createState() => _ReactionOverlayState();
}

const _maxParticles = 14;
const _lifetime = Duration(milliseconds: 2800);
const _stillLifetime = Duration(milliseconds: 1400);

class _Particle {
  _Particle({
    required this.reaction,
    required this.name,
    required this.spawnedAt,
    required this.lane,
    required this.wobblePhase,
    required this.wobbleAmplitude,
    required this.wobbleTurns,
    required this.scale,
  });

  final PTReaction reaction;
  final String name;
  final Duration spawnedAt;
  final double lane;
  final double wobblePhase;
  final double wobbleAmplitude;
  final double wobbleTurns;
  final double scale;
}

class _ReactionOverlayState extends State<ReactionOverlay> with SingleTickerProviderStateMixin {
  final _particles = <_Particle>[];
  final _random = math.Random();

  late final Ticker _ticker;
  final _clock = ValueNotifier<Duration>(Duration.zero);

  StreamSubscription<ReactionEvent>? _subscription;
  bool _still = false;

  Duration get _life => _still ? _stillLifetime : _lifetime;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _subscription = widget.reactions.listen(_spawn);
    unawaited(widget.assets.preload());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = reducedMotion(context);
  }

  @override
  void didUpdateWidget(ReactionOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.reactions, widget.reactions)) {
      _subscription?.cancel();
      _subscription = widget.reactions.listen(_spawn);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _spawn(ReactionEvent event) {
    if (!mounted) return;
    final reaction = reactionForEmoji(event.emoji);
    if (reaction == null) return;

    if (!_ticker.isActive) {
      _clock.value = Duration.zero;
      _ticker.start();
    }

    setState(() {
      if (_particles.length >= _maxParticles) _particles.removeAt(0);
      _particles.add(
        _Particle(
          reaction: reaction,
          name: event.displayName,
          spawnedAt: _clock.value,
          lane: _random.nextDouble(),
          wobblePhase: _random.nextDouble() * 2 * math.pi,
          wobbleAmplitude: 10 + _random.nextDouble() * 12,
          wobbleTurns: 1.3 + _random.nextDouble(),
          scale: 0.9 + _random.nextDouble() * 0.2,
        ),
      );
    });
  }

  void _onTick(Duration elapsed) {
    _clock.value = elapsed;
    final life = _life;
    if (!_particles.any((p) => elapsed - p.spawnedAt >= life)) return;
    setState(() => _particles.removeWhere((p) => elapsed - p.spawnedAt >= life));
    if (_particles.isEmpty) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    if (_particles.isEmpty) return const SizedBox.shrink();
    final tileWidth = widget.compact ? 104.0 : 128.0;
    final emojiSize = widget.compact ? 46.0 : 58.0;

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rise = constraints.maxHeight * 0.5;
          final laneWidth = math.max(0.0, math.min(constraints.maxWidth * 0.42, 280.0) - tileWidth);
          return ValueListenableBuilder<Duration>(
            valueListenable: _clock,
            builder: (context, now, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final particle in _particles)
                    _tile(particle, now, rise, laneWidth, tileWidth, emojiSize),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _tile(
    _Particle particle,
    Duration now,
    double rise,
    double laneWidth,
    double tileWidth,
    double emojiSize,
  ) {
    final since = now - particle.spawnedAt;
    final t = (since.inMicroseconds / _life.inMicroseconds).clamp(0.0, 1.0);

    final travel = _still ? 0.0 : rise * (0.35 * t + 0.65 * PTMotion.enter.transform(t));
    final wobble = _still
        ? 0.0
        : particle.wobbleAmplitude *
              math.sin(particle.wobblePhase + t * particle.wobbleTurns * 2 * math.pi);

    final grow = _still ? 1.0 : PTMotion.arrive.transform((t / 0.16).clamp(0.0, 1.0));
    final scale = particle.scale * (_still ? 1.0 : 0.55 + 0.45 * grow);

    const fadeFrom = 0.66;
    final opacity = t <= fadeFrom ? 1.0 : 1 - (t - fadeFrom) / (1 - fadeFrom);

    return Positioned(
      left: 16 + particle.lane * laneWidth + wobble,
      bottom: widget.spawnBottom + travel,
      width: tileWidth,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: Column(
            mainAxisSize: .min,
            children: [
              SizedBox.square(dimension: emojiSize, child: _art(particle, since, emojiSize)),
              const SizedBox(height: 2),
              Text(
                particle.name,
                maxLines: 1,
                overflow: .ellipsis,
                textAlign: .center,
                style: PTText.caption.copyWith(
                  fontSize: widget.compact ? 11 : 12,
                  color: PTColors.white(0.85),
                  shadows: const [
                    Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _art(_Particle particle, Duration since, double emojiSize) {
    final composition = widget.assets.of(particle.reaction);
    if (composition == null) {
      return Center(
        child: Text(particle.reaction.emoji, style: TextStyle(fontSize: emojiSize * 0.8)),
      );
    }
    final frames = composition.duration.inMicroseconds;
    final progress = _still || frames == 0 ? 0.0 : (since.inMicroseconds % frames) / frames;
    return RawLottie(composition: composition, progress: progress, fit: .contain);
  }
}
