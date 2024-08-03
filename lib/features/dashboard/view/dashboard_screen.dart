import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/auth/view/auth_screen.dart';
import 'package:playtogether/features/dashboard/view/account_screen.dart';
import 'package:playtogether/features/dashboard/view/add_friends_screen.dart';
import 'package:playtogether/features/dashboard/view/friends_screen.dart';

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
      body: IndexedStack(
        index: selectedScreenIndex,
        children: const [
          FriendsScreen(),
          AddFriendsScreen(),
          AccountScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedScreenIndex,
        onTap: (index) => setState(() => selectedScreenIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Friends',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_add_outlined),
            activeIcon: Icon(Icons.person_add),
            label: 'Add Friend',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
