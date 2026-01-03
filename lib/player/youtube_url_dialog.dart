import 'package:flutter/material.dart';

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
      setState(() => _errorMessage = 'Please enter a URL');
      return;
    }

    // Validate YouTube URL format
    if (!_isValidYoutubeUrl(url)) {
      setState(() => _errorMessage = 'Invalid YouTube URL');
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
    final colors = Theme.of(context).colorScheme;
    final typography = Theme.of(context).textTheme;

    return AlertDialog(
      content: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            Text('Enter YouTube URL', style: typography.headlineSmall),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'https://youtube.com/watch?v=...',
                      errorText: _errorMessage,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onSubmitted: (_) => _submitUrl(),
                    onChanged: (_) {
                      if (_errorMessage != null) setState(() => _errorMessage = null);
                    },
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: _submitUrl,
                  icon: Icon(Icons.arrow_forward),
                  tooltip: 'Load video',
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
