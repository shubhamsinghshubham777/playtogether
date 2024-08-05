import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:playtogether/assets.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/auth/view/auth_screen.dart';
import 'package:playtogether/features/dashboard/view/account_screen.dart';
import 'package:playtogether/features/dashboard/view/friends/add_friends_bottom_sheet.dart';
import 'package:playtogether/features/dashboard/view/friends/friends_screen.dart';
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: const Offset(0, 3),
              child: Image.asset(Assets.imageAppLogo, width: 24),
            ),
            const SizedBox(width: 12),
            const Text('PlayTogether'),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _showModalBottomSheet(
              context: context,
              child: const AccountScreen(),
            ),
            icon: const Icon(Icons.settings),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: const FriendsScreen(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showModalBottomSheet(
          context: context,
          child: const AddFriendsBottomSheet(),
        ),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Friends'),
      ),
    );
  }
}

void _showModalBottomSheet({
  required BuildContext context,
  required Widget child,
}) {
  showModalBottomSheet(
    context: context,
    builder: (_) => child,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxWidth: 600,
      maxHeight:
          context.height * (!isDesktop && context.isLandscape ? 1 : 0.75),
    ),
  );
}
