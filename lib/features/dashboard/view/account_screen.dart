import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserData = ref.watch(currentUserDataProvider).valueOrNull;
    final userNotifier = ref.watch(currentUserIdProvider.notifier);

    return Scaffold(
      body: Column(
        children: [
          Text('currentUserData: $currentUserData'),
          FilledButton(
            onPressed: userNotifier.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
