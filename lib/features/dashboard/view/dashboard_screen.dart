import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/auth/provider/user_providers.dart';
import 'package:playtogether/features/auth/view/auth_screen.dart';
import 'package:playtogether/features/call/view/call_screen.dart';
import 'package:playtogether/features/dashboard/view/add_friends_screen.dart';
import 'package:playtogether/utils.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int selectedScreenIndex = 0;
  final _calleeEmailController = TextEditingController();
  DocumentSnapshot? incomingCallData;

  @override
  void initState() {
    postFrameCallBack(_observeIncomingCall);
    super.initState();
  }

  @override
  void setState(VoidCallback fn) {
    if (!mounted) {
      return;
    }

    super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final userNotifier = ref.watch(authenticatedUserProvider.notifier);

    final incomingCallUser =
        ref.watch(userProvider(uid: incomingCallData?['callerId'])).valueOrNull;

    ref.listen(authenticatedUserProvider, (oldState, newState) {
      if (oldState?.valueOrNull != null && newState.valueOrNull == null) {
        context.pushAndRemoveUntil(const AuthScreen());
      }
    });

    return Scaffold(
      body: IndexedStack(
        index: selectedScreenIndex,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Dashboard'),
              if (incomingCallData != null && incomingCallUser != null)
                Row(
                  children: [
                    if (incomingCallUser.photoURL != null)
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: Image.network(incomingCallUser.photoURL!),
                      ),
                    Flexible(
                      child: Text('${incomingCallUser.name} is calling you'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final currentUser = await ref.read(
                          authenticatedUserProvider.future,
                        );
                        if (currentUser != null) {
                          deleteCallRelatedData(currentUser.uid);
                        }
                      },
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final currentUser = await ref.read(
                          authenticatedUserProvider.future,
                        );
                        if (currentUser != null) {
                          _joinCall(
                            callerId: incomingCallUser.uid,
                            calleeId: currentUser.uid,
                            offer: incomingCallData?['offer'],
                          );
                        }
                      },
                      child: const Text('Answer'),
                    ),
                  ],
                ),
              FilledButton(
                onPressed: userNotifier.signOut,
                child: const Text('Sign out'),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: TextField(
                  controller: _calleeEmailController,
                  decoration: const InputDecoration(
                    hintText: 'Enter email of who you want to call',
                  ),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final currentUser = await ref.read(
                    authenticatedUserProvider.future,
                  );
                  if (currentUser != null) {
                    _joinCall(
                      callerId: currentUser.uid,
                      calleeId: _calleeEmailController.text,
                    );
                  }
                },
                child: const Text('Call'),
              ),
            ],
          ),
          const AddFriendsScreen(),
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
        ],
      ),
    );
  }

  Future<void> _observeIncomingCall() async {
    final currentUser = await ref.read(authenticatedUserProvider.future);
    if (currentUser != null) {
      FirebaseFirestore.instance
          .collection('calls')
          .doc(currentUser.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.data()?.containsKey('callerId') ?? false) {
          debugPrint('New incoming call data: ${snapshot.data()}');
          setState(() => incomingCallData = snapshot);
        } else {
          setState(() => incomingCallData = null);
        }
      });
    }
  }

  void _joinCall({
    required String callerId,
    required String calleeId,
    dynamic offer,
  }) {
    context.push(
      CallScreen(callerUid: callerId, calleeUid: calleeId, offer: offer),
    );
  }
}
