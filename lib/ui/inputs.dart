import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

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

class PTCodeInputState extends State<PTCodeInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String get value => _controller.text;

  void clear() => _controller.clear();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
    _focusNode.addListener(() => setState(() {}));
  }

  void _onText() {
    setState(() {});
    widget.onChanged(value);
    if (value.length == PTCodeInput.length) widget.onCompleted?.call(value);
  }

  @override
  void dispose() {
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
                  Expanded(child: _box(i < text.length ? text[i] : null, i == text.length)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(String? char, bool isCursor) {
    final active = char != null || (isCursor && _focusNode.hasFocus);
    return AnimatedContainer(
      duration: Durations.short2,
      height: widget.boxHeight,
      alignment: .center,
      decoration: BoxDecoration(
        color: PTColors.white(active ? 0.06 : 0.04),
        border: Border.all(
          color: active
              ? const Color(0xFFA78BFA).withValues(alpha: 0.5)
              : PTColors.white(char != null ? 0.12 : 0.09),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: char != null
          ? Text(char, style: PTText.code.copyWith(letterSpacing: 0, color: const Color(0xFFE9DCFF)))
          : isCursor && _focusNode.hasFocus
          ? const _BlinkingCaret()
          : null,
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

class _BlinkingCaretState extends State<_BlinkingCaret>
    with SingleTickerProviderStateMixin {
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
class PTSlider extends StatelessWidget {
  const PTSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.trackHeight = 5,
    this.thumbRadius = 8,
  });

  /// Normalized 0–1.
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double trackHeight;
  final double thumbRadius;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final clamped = value.clamp(0.0, 1.0);
        void update(Offset local, {bool end = false}) {
          final v = (local.dx / width).clamp(0.0, 1.0);
          onChanged(v);
          if (end) onChangeEnd?.call(v);
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: .opaque,
            onTapDown: (d) => update(d.localPosition),
            onTapUp: (d) => update(d.localPosition, end: true),
            onHorizontalDragUpdate: (d) => update(d.localPosition),
            onHorizontalDragEnd: (_) => onChangeEnd?.call(clamped),
            child: SizedBox(
              height: 20,
              child: Stack(
                alignment: .centerLeft,
                children: [
                  Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: PTColors.white(0.13),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: clamped,
                    child: Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        gradient: PTColors.barGradient,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (clamped * width - thumbRadius).clamp(0, width - thumbRadius * 2),
                    child: Container(
                      width: thumbRadius * 2,
                      height: thumbRadius * 2,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9DCFF),
                        shape: .circle,
                        boxShadow: [
                          BoxShadow(
                            color: PTColors.primary.withValues(alpha: 0.7),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
