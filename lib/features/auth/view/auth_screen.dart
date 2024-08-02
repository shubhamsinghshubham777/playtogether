import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/dashboard/view/dashboard_screen.dart';
import 'package:playtogether/utils.dart';
import 'package:window_manager/window_manager.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserIdState = ref.watch(currentUserIdProvider);
    final userNotifier = ref.watch(currentUserIdProvider.notifier);

    ref.listen(currentUserIdProvider, (_, newState) async {
      if (newState.valueOrNull != null) {
        if (isDesktop) {
          await windowManager.show();
          await windowManager.focus();
        }
        if (context.mounted) context.pushReplacement(const DashboardScreen());
      }
    });

    return Scaffold(
      body: Column(
        children: [
          Text('User is: $currentUserIdState'),
          FilledButton(
            onPressed: userNotifier.signInWithGoogle,
            child: const Text('Login with Google'),
          ),
        ],
      ),
    );
  }
}
