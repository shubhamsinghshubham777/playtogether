import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/platform.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/pt_theme.dart';

class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key, this.facecams = false});

  final bool facecams;

  static const _playback = <_Shortcut>[
    _Shortcut(['Space', 'K'], 'Play or pause'),
    _Shortcut(['J'], 'Seek back 10s'),
    _Shortcut(['L'], 'Seek forward 10s'),
    _Shortcut(['←'], 'Seek back 5s'),
    _Shortcut(['→'], 'Seek forward 5s'),
  ];

  static const _audio = <_Shortcut>[
    _Shortcut(['↑'], 'Volume up'),
    _Shortcut(['↓'], 'Volume down'),
    _Shortcut(['M'], 'Mute or unmute'),
  ];

  @override
  Widget build(BuildContext context) {
    final view = <_Shortcut>[
      const _Shortcut(['C'], 'Show or hide the chat panel'),
      if (facecams) const _Shortcut(['V'], 'Show or hide the facecams'),
      if (isDesktop) const _Shortcut(['F'], 'Enter or exit fullscreen'),
      const _Shortcut(['F1'], 'Privacy mode — black out the room, mute mic and cam'),
      const _Shortcut(['Esc'], 'Close the reaction strip, then chat, then fullscreen'),
    ];

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Text(
          'Keyboard shortcuts',
          textAlign: .center,
          style: PTText.screenTitle.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 8),
        Text(
          'These stay quiet while you\'re typing in chat.',
          textAlign: .center,
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.55)),
        ),
        const SizedBox(height: 20),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: .stretch,
                spacing: 18,
                children: [
                  _Section(title: 'Playback', shortcuts: _playback),
                  _Section(title: 'Audio', shortcuts: _audio),
                  _Section(title: 'View', shortcuts: view),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        PTButton(
          label: 'Got it',
          icon: Symbols.check_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _Shortcut {
  const _Shortcut(this.keys, this.description);

  final List<String> keys;
  final String description;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.shortcuts});

  final String title;
  final List<_Shortcut> shortcuts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        Text(
          title.toUpperCase(),
          style: PTText.finePrint.copyWith(
            fontSize: 10.5,
            letterSpacing: 1.4,
            color: PTColors.white(0.4),
          ),
        ),
        for (final shortcut in shortcuts) _ShortcutRow(shortcut: shortcut),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.shortcut});

  final _Shortcut shortcut;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        SizedBox(
          width: 92,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final key in shortcut.keys) _KeyCap(label: key)],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              shortcut.description,
              style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.75)),
            ),
          ),
        ),
      ],
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: .center,
      decoration: BoxDecoration(
        color: PTColors.white(0.06),
        border: Border.all(color: PTColors.white(0.14)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: PTText.mono.copyWith(fontSize: 11.5, color: PTColors.textAccent)),
    );
  }
}
