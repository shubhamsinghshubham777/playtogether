import 'package:flutter/material.dart';

class UsernameDialog extends StatelessWidget {
  const UsernameDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const UsernameDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Who are you?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          _UsernameOption(
            name: 'Reet',
            color: colors.secondaryContainer,
            onTap: () => Navigator.of(context).pop('Reet'),
          ),
          _UsernameOption(
            name: 'Shubh',
            color: colors.primaryContainer,
            onTap: () => Navigator.of(context).pop('Shubh'),
          ),
        ],
      ),
    );
  }
}

class _UsernameOption extends StatelessWidget {
  const _UsernameOption({required this.name, required this.color, required this.onTap});

  final String name;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Text(
            name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
