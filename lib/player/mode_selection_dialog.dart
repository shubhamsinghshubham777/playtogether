import 'package:flutter/material.dart';

enum InitialMode { local, youtube }

class ModeSelectionDialog extends StatelessWidget {
  const ModeSelectionDialog({super.key});

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
            Text('Choose Video Source', style: typography.headlineSmall),
            Text(
              'Select how you want to watch videos together',
              style: typography.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Row(
              spacing: 16,
              children: [
                Expanded(
                  child: _ModeButton(
                    icon: Icons.video_file,
                    label: 'Local Video',
                    description: 'Play from file',
                    onPressed: () => Navigator.of(context).pop(InitialMode.local),
                  ),
                ),
                Expanded(
                  child: _ModeButton(
                    icon: Icons.play_circle_outline,
                    label: 'YouTube',
                    description: 'Play from URL',
                    onPressed: () => Navigator.of(context).pop(InitialMode.youtube),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(icon, size: 48, color: colors.primary),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            Text(
              description,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
