import 'dart:ui';
import 'package:flutter/material.dart';

class MediaSharingPromptResult {
  const MediaSharingPromptResult({required this.shouldShare, required this.rememberChoice});

  final bool shouldShare;
  final bool rememberChoice;
}

Future<MediaSharingPromptResult?> showMediaSharingPromptDialog({
  required BuildContext context,
  required String fileName,
  required int fileSize,
}) {
  return showDialog<MediaSharingPromptResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MediaSharingPromptDialog(fileName: fileName, fileSize: fileSize),
  );
}

class _MediaSharingPromptDialog extends StatefulWidget {
  const _MediaSharingPromptDialog({required this.fileName, required this.fileSize});

  final String fileName;
  final int fileSize;

  @override
  State<_MediaSharingPromptDialog> createState() => _MediaSharingPromptDialogState();
}

class _MediaSharingPromptDialogState extends State<_MediaSharingPromptDialog> {
  bool _rememberChoice = false;

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeFormatted = _formatSize(widget.fileSize);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.cloud_upload_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Text('Share with room?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Would you like to share "${widget.fileName}" ($sizeFormatted) with everyone in the room?',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sharing uploads the file to the cloud so room members can watch seamlessly without needing a local copy.',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _rememberChoice,
                  onChanged: (val) => setState(() => _rememberChoice = val ?? false),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _rememberChoice = !_rememberChoice),
                    child: Text(
                      "Remember my choice for future files",
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(
                context,
              ).pop(MediaSharingPromptResult(shouldShare: false, rememberChoice: _rememberChoice));
            },
            child: const Text('Play Locally Only'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_upload, size: 18),
            label: const Text('Share with Room'),
            onPressed: () {
              Navigator.of(
                context,
              ).pop(MediaSharingPromptResult(shouldShare: true, rememberChoice: _rememberChoice));
            },
          ),
        ],
      ),
    );
  }
}
