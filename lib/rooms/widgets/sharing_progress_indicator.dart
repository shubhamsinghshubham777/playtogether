import 'dart:ui';
import 'package:flutter/material.dart';

class SharingProgressIndicator extends StatelessWidget {
  const SharingProgressIndicator({
    super.key,
    required this.fraction,
    required this.speedBps,
    required this.etaSeconds,
    required this.state,
    this.label = 'Uploading video...',
    this.onCancel,
    this.onRetry,
  });

  final double fraction;
  final double speedBps;
  final int etaSeconds;
  final String state;
  final String label;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }

  String _formatEta(int seconds) {
    if (seconds <= 0) return '';
    if (seconds >= 60) {
      final mins = seconds ~/ 60;
      final remSecs = seconds % 60;
      return '${mins}m ${remSecs}s';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = (fraction * 100).clamp(0, 100).toInt();
    final isDone = state == 'ready' || fraction >= 1.0;
    final isFailed = state == 'failed';

    final speedText = _formatSpeed(speedBps);
    final etaText = _formatEta(etaSeconds);
    final stats = [
      if (speedText.isNotEmpty) speedText,
      if (etaText.isNotEmpty) 'ETA $etaText',
    ].join(' • ');

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFailed
                  ? theme.colorScheme.error.withValues(alpha: 0.5)
                  : theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    isDone
                        ? Icons.check_circle_outline
                        : isFailed
                        ? Icons.error_outline
                        : Icons.cloud_upload_outlined,
                    size: 18,
                    color: isDone
                        ? Colors.green
                        : isFailed
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$percentage%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDone
                          ? Colors.green
                          : isFailed
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                  if (onCancel != null && !isDone) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      splashRadius: 16,
                      onPressed: onCancel,
                    ),
                  ],
                  if (onRetry != null && isFailed) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      splashRadius: 16,
                      onPressed: onRetry,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: isDone ? 1.0 : (isFailed ? 0.0 : fraction),
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDone
                        ? Colors.green
                        : isFailed
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              if (stats.isNotEmpty && !isDone && !isFailed) ...[
                const SizedBox(height: 6),
                Text(
                  stats,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
