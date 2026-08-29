import 'package:flutter/material.dart';

class MediaSharingToggle extends StatelessWidget {
  const MediaSharingToggle({
    super.key,
    required this.enabled,
    required this.canShare,
    required this.tierLabel,
    required this.onChanged,
    this.onUpgradeTap,
  });

  final bool enabled;
  final bool canShare;
  final String tierLabel;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onUpgradeTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: 20,
            color: enabled ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Share file with room',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                tierLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          if (canShare)
            Switch.adaptive(
              value: enabled,
              onChanged: onChanged,
            )
          else if (onUpgradeTap != null)
            TextButton(
              onPressed: onUpgradeTap,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text('Upgrade'),
            ),
        ],
      ),
    );
  }
}
