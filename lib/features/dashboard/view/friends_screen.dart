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

  @override
  void initState() {
    postFrameCallBack(_observeIncomingCall);
    super.initState();
  }

  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserData = ref.watch(currentUserDataProvider).valueOrNull;

    final incomingCallUser =
        ref.watch(userProvider(uid: incomingCallData?['callerId'])).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: true,
      ),
      body: Column(
        children: [
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
          if (currentUserData?.friendsUids.isNotEmpty ?? false)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your friends'),
                  Expanded(
                    child: ListView.builder(
                      itemCount: currentUserData?.friendsUids.length,
                      itemBuilder: (_, index) {
                        final uid = currentUserData!.friendsUids[index];
                        return _FriendListTile(key: ValueKey(uid), uid: uid);
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (currentUserData?.friendRequestsUids.isNotEmpty ?? false)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Your friend requests'),
                  Expanded(
                    child: ListView.builder(
                      itemCount: currentUserData?.friendRequestsUids.length,
                      itemBuilder: (_, index) {
                        final uid = currentUserData!.friendRequestsUids[index];
                        return _FriendRequestListTile(
                            key: ValueKey(uid), uid: uid);
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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
    final friendUpdater = ref.watch(friendshipStateProvider(uid: uid).notifier);

    if (friend == null || currentUser == null) return const SizedBox.shrink();

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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_forward),
          IconButton(
            onPressed: () => friendUpdater.unfriend(uid: uid),
            icon: const Icon(Icons.person_remove),
          ),
        ],
      ),
    );
  }
}

class _FriendRequestListTile extends ConsumerWidget {
  const _FriendRequestListTile({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserDataProvider).valueOrNull;
    final friend = ref.watch(userProvider(uid: uid)).valueOrNull;
    final friendUpdater = ref.watch(friendshipStateProvider(uid: uid).notifier);

    if (friend == null || currentUser == null) {
      return const SizedBox.shrink();
    }

    return ListTile(
      leading: friend.photoURL != null
          ? Image.network(friend.photoURL!, width: 32, height: 32)
          : null,
      title: Text(friend.name ?? ''),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => friendUpdater.rejectFriendRequest(uid: uid),
            icon: const Icon(Icons.close),
          ),
          IconButton(
            onPressed: () => friendUpdater.acceptFriendRequest(uid: uid),
            icon: const Icon(Icons.check),
          ),
        ],
      ),
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
