import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/auth/view/auth_screen.dart';
import 'package:playtogether/features/dashboard/view/account_screen.dart';
import 'package:playtogether/features/dashboard/view/add_friends_bottom_sheet.dart';
import 'package:playtogether/features/dashboard/view/friends_screen.dart';
import 'package:playtogether/utils.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int selectedScreenIndex = 0;

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserIdProvider, (oldState, newState) {
      if (oldState?.valueOrNull != null && newState.valueOrNull == null) {
        context.pushAndRemoveUntil(const AuthScreen());
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlayTogether'),
        centerTitle: true,
        elevation: 16,
        scrolledUnderElevation: 16,
        actions: [
          IconButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              builder: (_) => const AccountScreen(),
              showDragHandle: true,
            ),
            icon: const Icon(Icons.settings),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const FriendsScreen(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          builder: (_) => const AddFriendsBottomSheet(),
          showDragHandle: true,
          isScrollControlled: true,
          constraints: BoxConstraints(
            maxHeight:
                context.height * (!isDesktop && context.isLandscape ? 1 : 0.75),
          ),
        ),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
