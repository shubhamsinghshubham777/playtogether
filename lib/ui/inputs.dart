import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'pt_motion.dart';
import 'pt_theme.dart';

class PTTextField extends StatefulWidget {
  const PTTextField({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.maxLength,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final String? errorText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final int? maxLength;
  final bool enabled;

  @override
  State<PTTextField> createState() => _PTTextFieldState();
}

class _PTTextFieldState extends State<PTTextField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final borderColor = hasError
        ? PTColors.dangerBorder.withValues(alpha: 0.55)
        : _focusNode.hasFocus
        ? const Color(0xFFA78BFA).withValues(alpha: 0.55)
        : PTColors.white(0.12);

    return Column(
      crossAxisAlignment: .start,
      spacing: 7,
      children: [
        if (widget.label != null) Text(widget.label!, style: PTText.caption),
        AnimatedContainer(
          duration: Durations.short2,
          decoration: BoxDecoration(
            color: PTColors.white(widget.enabled ? 0.06 : 0.04),
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              if (widget.prefixIcon != null)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Icon(widget.prefixIcon, size: 18, color: PTColors.white(0.45)),
                ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  autofocus: widget.autofocus,
                  enabled: widget.enabled,
                  maxLength: widget.maxLength,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: PTText.body.copyWith(fontSize: 14.5),
                  cursorColor: PTColors.textAccent,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.45)),
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              if (widget.suffixIcon != null)
                Padding(padding: const EdgeInsets.only(right: 14), child: widget.suffixIcon),
            ],
          ),
        ),
        if (hasError)
          Row(
            spacing: 6,
            children: [
              const Icon(Symbols.error_rounded, size: 15, fill: 1, color: PTColors.danger),
              Flexible(
                child: Text(
                  widget.errorText!,
                  style: PTText.finePrint.copyWith(fontSize: 12.5, color: PTColors.danger),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Six segmented boxes for the room join code (unambiguous alphabet).
class PTCodeInput extends StatefulWidget {
  const PTCodeInput({super.key, required this.onChanged, this.onCompleted, this.boxHeight = 58});

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final double boxHeight;

  static const length = 6;
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  @override
  State<PTCodeInput> createState() => PTCodeInputState();
}

class PTCodeInputState extends State<PTCodeInput> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// Runs the left-to-right "ready to go" flourish once the sixth character
  /// lands. Each box reads its own slice of this, staggered by index.
  late final AnimationController _complete = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  String get value => _controller.text;

  void clear() => _controller.clear();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
    _focusNode.addListener(() => setState(() {}));
  }

  void _onText() {
    final wasComplete = _complete.value > 0 && _complete.isCompleted;
    setState(() {});
    widget.onChanged(value);
    if (value.length == PTCodeInput.length) {
      if (!wasComplete && !reducedMotion(context)) _complete.forward(from: 0);
      widget.onCompleted?.call(value);
    } else {
      _complete.value = 0;
    }
  }

  @override
  void dispose() {
    _complete.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = value;
    return GestureDetector(
      behavior: .opaque,
      onTap: () => _focusNode.requestFocus(),
      child: Stack(
        children: [
          // Invisible real field: keeps IME/paste/desktop keyboard handling native.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLength: PTCodeInput.length,
                textCapitalization: .characters,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  FilteringTextInputFormatter.allow(RegExp('[${PTCodeInput.alphabet}]')),
                ],
                decoration: const InputDecoration(counterText: ''),
              ),
            ),
          ),
          IgnorePointer(
            child: Row(
              spacing: 9,
              children: [
                for (var i = 0; i < PTCodeInput.length; i++)
                  Expanded(child: _box(i < text.length ? text[i] : null, i == text.length, i)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(String? char, bool isCursor, int index) {
    final active = char != null || (isCursor && _focusNode.hasFocus);
    return AnimatedBuilder(
      animation: _complete,
      builder: (context, _) {
        // Each box gets a 25 ms-offset window of the shared controller, so the
        // pulse sweeps left to right rather than flashing all six at once.
        final start = index * 0.12;
        final local = ((_complete.value - start) / 0.4).clamp(0.0, 1.0);
        final pulse = math.sin(local * math.pi);
        return AnimatedContainer(
          duration: PTMotion.functional(context, PTMotion.hover),
          height: widget.boxHeight,
          alignment: .center,
          decoration: BoxDecoration(
            color: PTColors.white(active ? 0.06 : 0.04),
            border: Border.all(
              color: Color.lerp(
                active
                    ? const Color(0xFFA78BFA).withValues(alpha: 0.5)
                    : PTColors.white(char != null ? 0.12 : 0.09),
                const Color(0xFFC9B8FF),
                pulse,
              )!,
              width: 1 + pulse,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: char != null
              ? Text(
                  char,
                  style: PTText.code.copyWith(letterSpacing: 0, color: const Color(0xFFE9DCFF)),
                )
              : isCursor && _focusNode.hasFocus
              ? const _BlinkingCaret()
              : null,
        );
      },
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _BlinkingCaret extends StatefulWidget {
  const _BlinkingCaret();

  @override
  State<_BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<_BlinkingCaret> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: TweenSequence<double>([
        TweenSequenceItem(tween: ConstantTween(1), weight: 1),
        TweenSequenceItem(tween: ConstantTween(0), weight: 1),
      ]).animate(_controller),
      child: Container(width: 2, height: 24, color: PTColors.textAccent),
    );
  }
}

/// Progress/duration slider with the violet gradient fill.
class PTSlider extends StatefulWidget {
  const PTSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.onHover,
    this.trackHeight = 5,
    this.thumbRadius = 8,
    this.enabled = true,
  });

  /// Normalized 0–1.
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Reports the normalized (0–1) position under a hovering pointer, and null
  /// when it leaves. Desktop-only in practice — touch never hovers.
  final ValueChanged<double?>? onHover;
  final double trackHeight;
  final double thumbRadius;

  /// False dims the track and drops every gesture, matching [PTButton]'s
  /// disabled treatment.
  final bool enabled;

  @override
  State<PTSlider> createState() => _PTSliderState();
}

class _PTSliderState extends State<PTSlider> {
  bool _active = false;

  void _setActive(bool value) {
    if (_active == value) return;
    setState(() => _active = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final onHover = widget.onHover;
    final clamped = widget.value.clamp(0.0, 1.0);
    // No LayoutBuilder here: it can't answer intrinsic-size queries, so it
    // would crash inside IntrinsicHeight (e.g. the lobby's equal-height cards).
    void update(Offset local, {bool end = false}) {
      final width = context.size?.width ?? 0;
      if (width <= 0) return;
      final v = (local.dx / width).clamp(0.0, 1.0);
      widget.onChanged(v);
      if (end) widget.onChangeEnd?.call(v);
    }

    void hover(Offset local) {
      final width = context.size?.width ?? 0;
      if (width <= 0) return;
      onHover?.call((local.dx / width).clamp(0.0, 1.0));
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => _setActive(true) : null,
      onHover: onHover == null || !enabled ? null : (e) => hover(e.localPosition),
      onExit: !enabled
          ? null
          : (_) {
              _setActive(false);
              onHover?.call(null);
            },
      child: GestureDetector(
        behavior: .opaque,
        // Scrub behaviour is untouched: the thumb grows, but the value still
        // previews locally and only broadcasts on release.
        onTapDown: enabled ? (d) => update(d.localPosition) : null,
        onTapUp: enabled ? (d) => update(d.localPosition, end: true) : null,
        onHorizontalDragStart: enabled ? (_) => _setActive(true) : null,
        onHorizontalDragUpdate: enabled ? (d) => update(d.localPosition) : null,
        onHorizontalDragEnd: enabled
            ? (_) {
                widget.onChangeEnd?.call(clamped);
                _setActive(false);
              }
            : null,
        child: AnimatedOpacity(
          duration: PTMotion.functional(context, PTMotion.hover),
          opacity: enabled ? 1 : 0.45,
          child: SizedBox(
            height: 20,
            width: double.infinity,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _active && enabled ? 1.0 : 0.0),
              duration: PTMotion.functional(context, PTMotion.hover),
              curve: PTMotion.enter,
              builder: (context, grow, _) => CustomPaint(
                painter: _PTSliderPainter(
                  value: clamped,
                  trackHeight: widget.trackHeight,
                  thumbRadius: widget.thumbRadius + 2 * grow,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PTSliderPainter extends CustomPainter {
  const _PTSliderPainter({
    required this.value,
    required this.trackHeight,
    required this.thumbRadius,
  });

  final double value;
  final double trackHeight;
  final double thumbRadius;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(999);
    final trackTop = (size.height - trackHeight) / 2;

    final trackRect = Rect.fromLTWH(0, trackTop, size.width, trackHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = PTColors.white(0.13),
    );

    if (value > 0) {
      final fillRect = Rect.fromLTWH(0, trackTop, size.width * value, trackHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, radius),
        Paint()..shader = PTColors.barGradient.createShader(fillRect),
      );
    }

    final center = Offset(
      (value * size.width).clamp(thumbRadius, size.width - thumbRadius),
      size.height / 2,
    );
    canvas.drawCircle(
      center.translate(0, 2),
      thumbRadius,
      Paint()
        ..color = PTColors.primary.withValues(alpha: 0.7)
        ..maskFilter = MaskFilter.blur(.normal, Shadow.convertRadiusToSigma(8)),
    );
    canvas.drawCircle(center, thumbRadius, Paint()..color = const Color(0xFFE9DCFF));
  }

  @override
  bool shouldRepaint(_PTSliderPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.thumbRadius != thumbRadius;
}
