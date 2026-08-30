import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/platform.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/pt_motion.dart';
import 'package:playtogether/ui/pt_theme.dart';

class ExtendRoomDialog extends StatefulWidget {
  const ExtendRoomDialog({super.key, required this.options, required this.headroomMinutes});

  final List<int> options;
  final int headroomMinutes;

  @override
  State<ExtendRoomDialog> createState() => _ExtendRoomDialogState();
}

class _ExtendRoomDialogState extends State<ExtendRoomDialog> {
  late int _selected = widget.options.first;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        Row(
          spacing: 13,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: PTColors.primary.withValues(alpha: 0.2),
                border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Symbols.more_time_rounded,
                size: 24,
                fill: 1,
                color: PTColors.textAccent,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text('Keep it going', style: PTText.cardHeading),
                  Text(
                    '${_label(widget.headroomMinutes)} of room time left to spend',
                    style: PTText.caption.copyWith(fontSize: 12, fontWeight: .w400),
                  ),
                ],
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final minutes in widget.options)
              _Choice(
                label: _label(minutes),
                selected: _selected == minutes,
                onTap: () => setState(() => _selected = minutes),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            spacing: 11,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Not now',
                  variant: .secondary,
                  height: 48,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: PTButton(
                  label: 'Add ${_label(_selected)}',
                  height: 48,
                  onPressed: () => Navigator.of(context).pop(_selected),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _label(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: PTMotion.functional(context, PTMotion.hover),
          curve: PTMotion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? PTColors.primary.withValues(alpha: 0.25) : PTColors.white(0.06),
            border: Border.all(
              color: selected
                  ? const Color(0xFFA78BFA).withValues(alpha: 0.55)
                  : PTColors.white(0.12),
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: PTText.mono.copyWith(
              fontSize: 14,
              color: selected ? PTColors.textAccent : PTColors.white(0.75),
            ),
          ),
        ),
      ),
    );
  }
}

class PremiumTeaseDialog extends StatelessWidget {
  const PremiumTeaseDialog({
    super.key,
    required this.headline,
    required this.body,
    required this.perks,
    this.onNotify,
    this.onUpgrade,
    this.onSignIn,
    this.desktopOverride,
  });

  final String headline;
  final String body;
  final List<String> perks;
  final VoidCallback? onNotify;
  final VoidCallback? onUpgrade;
  final VoidCallback? onSignIn;
  final bool? desktopOverride;

  bool get _isDesktop => desktopOverride ?? isDesktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        Row(
          spacing: 13,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: PTColors.brandGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Symbols.workspace_premium_rounded,
                size: 24,
                fill: 1,
                color: Colors.white,
              ),
            ),
            Expanded(child: Text(headline, style: PTText.cardHeading)),
          ],
        ),
        Text(
          body,
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.55),
        ),
        Column(
          crossAxisAlignment: .start,
          spacing: 9,
          children: [
            for (final perk in perks)
              Row(
                spacing: 10,
                children: [
                  const Icon(
                    Symbols.check_circle_rounded,
                    size: 17,
                    fill: 1,
                    color: PTColors.textAccent,
                  ),
                  Expanded(
                    child: Text(
                      perk,
                      style: PTText.body.copyWith(fontSize: 13, color: PTColors.white(0.72)),
                    ),
                  ),
                ],
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: onSignIn == null ? _teaseActions(context) : _signInActions(context),
        ),
      ],
    );
  }

  Widget _teaseActions(BuildContext context) {
    if (_isDesktop) {
      return Row(
        spacing: 11,
        children: [
          Expanded(
            child: PTButton(
              label: 'Maybe later',
              variant: .secondary,
              height: 48,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: PTButton(
              label: 'Go Premium',
              icon: Symbols.crown_rounded,
              height: 48,
              onPressed: () {
                Navigator.of(context).pop();
                (onUpgrade ?? onNotify)?.call();
              },
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 11,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: PTColors.white(0.04),
            border: Border.all(color: PTColors.white(0.08)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Subscriptions are managed on our website.',
            textAlign: TextAlign.center,
            style: PTText.body.copyWith(fontSize: 13, color: PTColors.white(0.7)),
          ),
        ),
        PTButton(
          label: 'Close',
          variant: .secondary,
          height: 48,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _signInActions(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 11,
      children: [
        GoogleButton(
          label: 'Sign in with Google',
          onPressed: () {
            Navigator.of(context).pop();
            onSignIn?.call();
          },
        ),
        PTButton(
          label: 'Maybe later',
          variant: .secondary,
          height: 48,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
