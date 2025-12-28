import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

class ChooserDialog<T> extends StatelessWidget {
  const ChooserDialog({
    super.key,
    required this.type,
    required this.values,
    required this.onChosen,
  });

  final String type;
  final Iterable<T> values;
  final ValueChanged<T> onChosen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final typography = Theme.of(context).textTheme;

    return AlertDialog(
      content: Container(
        decoration: BoxDecoration(color: colors.surfaceContainer, borderRadius: .circular(16)),
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            spacing: 16,
            children: [
              Text('Choose $type Track', style: typography.headlineSmall),
              ...values.map<Widget?>((value) {
                final title = value is SubtitleTrack
                    ? value.title
                    : value is AudioTrack
                    ? value.language
                    : '';
                if (title == null || title.isEmpty == true) return null;
                return ListTile(onTap: () => onChosen(value), title: Text(title));
              }).nonNulls,
            ],
          ),
        ),
      ),
    );
  }
}
