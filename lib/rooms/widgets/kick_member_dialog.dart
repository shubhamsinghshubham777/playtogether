import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/pt_theme.dart';

/// Body for [showGlassDialog]. Pops `true` to remove and let them back in,
/// `false` to remove and bar them for the life of the room, null to cancel —
/// the per-kick choice of D9, rather than a room-wide ban setting.
class KickMemberDialog extends StatefulWidget {
  const KickMemberDialog({super.key, required this.displayName});

  final String displayName;

  @override
  State<KickMemberDialog> createState() => _KickMemberDialogState();
}

class _KickMemberDialogState extends State<KickMemberDialog> {
  bool _allowRejoin = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Text(
          'Remove ${widget.displayName}?',
          textAlign: .center,
          style: PTText.screenTitle.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 8),
        Text(
          "They'll be taken back to the lobby.",
          textAlign: .center,
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.55)),
        ),
        const SizedBox(height: 18),
        _RejoinToggle(value: _allowRejoin, onChanged: (v) => setState(() => _allowRejoin = v)),
        const SizedBox(height: 18),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: PTButton(
                label: 'Cancel',
                variant: .secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: PTButton(
                label: 'Remove',
                variant: .destructive,
                onPressed: () => Navigator.of(context).pop(_allowRejoin),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RejoinToggle extends StatelessWidget {
  const _RejoinToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: .opaque,
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: PTColors.white(0.05),
            border: Border.all(color: PTColors.white(0.12)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            spacing: 12,
            children: [
              AnimatedContainer(
                duration: Durations.short2,
                width: 22,
                height: 22,
                alignment: .center,
                decoration: BoxDecoration(
                  gradient: value ? PTColors.buttonGradient : null,
                  color: value ? null : PTColors.white(0.06),
                  border: Border.all(color: value ? Colors.transparent : PTColors.white(0.22)),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: value
                    ? const Icon(Symbols.check_rounded, size: 15, color: Colors.white)
                    : null,
              ),
              Expanded(
                child: Text(
                  'Let them rejoin with the room code',
                  style: PTText.body.copyWith(fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
