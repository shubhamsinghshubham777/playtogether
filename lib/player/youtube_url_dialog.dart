import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/inputs.dart';
import 'package:playtogether/ui/pt_theme.dart';

/// Body for [showGlassDialog]; pops the validated URL string.
class YouTubeUrlDialog extends StatefulWidget {
  const YouTubeUrlDialog({super.key});

  @override
  State<YouTubeUrlDialog> createState() => _YouTubeUrlDialogState();
}

class _YouTubeUrlDialogState extends State<YouTubeUrlDialog> {
  final _controller = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitUrl() {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Paste a link first.');
      return;
    }
    if (!_isValidYoutubeUrl(url)) {
      setState(() => _errorMessage = "Hmm, that doesn't look like a YouTube link.");
      return;
    }
    Navigator.of(context).pop(url);
  }

  bool _isValidYoutubeUrl(String url) {
    final patterns = [
      RegExp(r'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'm\.youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(url));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 16,
      children: [
        Column(
          crossAxisAlignment: .start,
          spacing: 5,
          children: [
            Text('Paste a YouTube link', style: PTText.screenTitle.copyWith(fontSize: 20)),
            Text(
              'It switches for everyone in the room.',
              style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.55)),
            ),
          ],
        ),
        PTTextField(
          controller: _controller,
          hint: 'youtube.com/watch?v=…',
          prefixIcon: Symbols.link_rounded,
          autofocus: true,
          errorText: _errorMessage,
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
          onSubmitted: (_) => _submitUrl(),
        ),
        Row(
          mainAxisAlignment: .end,
          spacing: 11,
          children: [
            PTButton(
              label: 'Cancel',
              variant: .secondary,
              height: 46,
              expand: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
            PTButton(
              label: 'Load video',
              trailingIcon: Symbols.arrow_forward_rounded,
              height: 46,
              expand: false,
              onPressed: _submitUrl,
            ),
          ],
        ),
      ],
    );
  }
}
