import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/ui/pt_theme.dart';

/// Body for [showGlassDialog]: audio/subtitle track picker styled per the
/// "Subtitles" dialog in the redesign.
class ChooserDialog<T> extends StatelessWidget {
  const ChooserDialog({
    super.key,
    required this.type,
    required this.values,
    required this.onChosen,
    this.selected,
  });

  final String type;
  final Iterable<T> values;
  final ValueChanged<T> onChosen;
  final T? selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(type, style: PTText.cardHeading),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              spacing: 6,
              children: values
                  .map<Widget?>((value) {
                    final title = value is SubtitleTrack
                        ? (value.title ?? value.language)
                        : value is AudioTrack
                        ? (value.language ?? value.title)
                        : value.toString();
                    if (title == null || title.isEmpty) return null;
                    return _TrackRow(
                      label: title,
                      isSelected: value == selected,
                      onTap: () => onChosen(value),
                    );
                  })
                  .nonNulls
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackRow extends StatefulWidget {
  const _TrackRow({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? PTColors.primary.withValues(alpha: 0.22)
                : _hovered
                ? PTColors.white(0.07)
                : Colors.transparent,
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFFA78BFA).withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: PTText.body.copyWith(
                    fontSize: 14.5,
                    color: widget.isSelected ? Colors.white : PTColors.white(0.8),
                  ),
                ),
              ),
              if (widget.isSelected)
                const Icon(
                  Symbols.check_circle_rounded,
                  size: 18,
                  fill: 1,
                  color: PTColors.textAccent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
