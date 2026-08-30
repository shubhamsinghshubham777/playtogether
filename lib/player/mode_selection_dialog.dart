import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';

enum InitialMode { local, youtube }

/// Body for [showGlassDialog]: "What are we watching?" source chooser.
class ModeSelectionDialog extends StatelessWidget {
  const ModeSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // The glass shell lands first, then its contents settle into it.
    return Column(
      mainAxisSize: .min,
      children: [
        PTEntrance(
          duration: PTMotion.state,
          offset: 8,
          child: Text('What are we watching?', style: PTText.screenTitle.copyWith(fontSize: 20)),
        ),
        const SizedBox(height: 8),
        PTEntrance(
          delay: const Duration(milliseconds: 40),
          duration: PTMotion.state,
          offset: 8,
          child: Text(
            'Pick a source — everyone stays in sync either way.',
            textAlign: .center,
            style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.55)),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          spacing: 14,
          children: [
            Expanded(
              child: PTEntrance(
                delay: const Duration(milliseconds: 80),
                duration: PTMotion.state,
                offset: 8,
                child: _SourceOption(
                  icon: Symbols.video_file_rounded,
                  label: 'Local file',
                  description: 'Play from your device',
                  onTap: () => Navigator.of(context).pop(InitialMode.local),
                ),
              ),
            ),
            Expanded(
              child: PTEntrance(
                delay: const Duration(milliseconds: 120),
                duration: PTMotion.state,
                offset: 8,
                child: _SourceOption(
                  icon: Symbols.smart_display_rounded,
                  label: 'YouTube',
                  description: 'Paste a link',
                  onTap: () => Navigator.of(context).pop(InitialMode.youtube),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SourceOption extends StatefulWidget {
  const _SourceOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  State<_SourceOption> createState() => _SourceOptionState();
}

class _SourceOptionState extends State<_SourceOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PTPressable(
        onTap: widget.onTap,
        // "What are we watching?" is the moment the evening starts — these
        // should feel like physical cards you pick up.
        child: AnimatedSlide(
          offset: _hovered ? const Offset(0, -0.012) : Offset.zero,
          duration: PTMotion.functional(context, PTMotion.hover),
          curve: PTMotion.enter,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
            decoration: BoxDecoration(
              color: _hovered ? PTColors.primary.withValues(alpha: 0.18) : PTColors.white(0.05),
              border: Border.all(
                color: _hovered
                    ? const Color(0xFFA78BFA).withValues(alpha: 0.5)
                    : PTColors.white(0.13),
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: .min,
              spacing: 9,
              children: [
                Icon(widget.icon, size: 38, fill: 1, color: PTColors.textAccent),
                Text(widget.label, style: PTText.buttonLabel),
                Text(
                  widget.description,
                  textAlign: .center,
                  style: PTText.finePrint.copyWith(color: PTColors.white(0.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
