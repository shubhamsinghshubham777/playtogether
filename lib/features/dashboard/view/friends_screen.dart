import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/call/view/call_screen.dart';
import 'package:playtogether/features/dashboard/provider/friend_provider.dart';
import 'package:playtogether/utils.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  DocumentSnapshot? incomingCallData;
  final _calleeEmailController = TextEditingController();

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
    final currentUserData = ref.watch(currentUserDataProvider).valueOrNull;
    final userNotifier = ref.watch(currentUserIdProvider.notifier);

    final incomingCallUser =
        ref.watch(userProvider(uid: incomingCallData?['callerId'])).valueOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('currentUserData: $currentUserData'),
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
                  final currentUserId = await ref.read(
                    currentUserIdProvider.future,
                  );
                  if (currentUserId != null) {
                    deleteCallRelatedData(currentUserId);
                  }
                },
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () async {
                  final currentUserId = await ref.read(
                    currentUserIdProvider.future,
                  );
                  if (currentUserId != null && context.mounted) {
                    _joinCall(
                      context: context,
                      callerId: incomingCallUser.uid,
                      calleeId: currentUserId,
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
            final currentUserId = await ref.read(
              currentUserIdProvider.future,
            );
            if (currentUserId != null && context.mounted) {
              _joinCall(
                context: context,
                callerId: currentUserId,
                calleeId: _calleeEmailController.text,
              );
            }
          },
          child: const Text('Call'),
        ),
        if (currentUserData?.friendsUids.isNotEmpty ?? false)
          Expanded(
            child: ListView.builder(
              itemCount: currentUserData?.friendsUids.length,
              itemBuilder: (listContext, index) {
                return _FriendListTile(
                  uid: currentUserData!.friendsUids[index],
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _observeIncomingCall() async {
    final currentUserId = await ref.read(currentUserIdProvider.future);
    if (currentUserId != null) {
      FirebaseFirestore.instance
          .collection('calls')
          .doc(currentUserId)
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
}

class _FriendListTile extends ConsumerWidget {
  const _FriendListTile({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserDataProvider).valueOrNull;
    final friend = ref.watch(userProvider(uid: uid)).valueOrNull;

    if (friend == null || currentUser == null) {
      return const SizedBox.shrink();
    }

    return ListTile(
      onTap: () => _joinCall(
        context: context,
        callerId: currentUser.uid,
        calleeId: friend.uid,
      ),
      leading: friend.photoURL != null
          ? Image.network(friend.photoURL!, width: 32, height: 32)
          : null,
      title: Text(friend.name ?? ''),
      trailing: const Icon(Icons.arrow_forward),
    );
  }
}

void _joinCall({
  required BuildContext context,
  required String callerId,
  required String calleeId,
  dynamic offer,
}) {
  context.push(
    CallScreen(callerUid: callerId, calleeUid: calleeId, offer: offer),
  );
}
