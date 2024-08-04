import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:playtogether/assets.dart';
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

    return Column(
      children: [
        if (incomingCallData != null && incomingCallUser != null)
          Row(
            children: [
              if (incomingCallUser.photoURL != null)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: FadeInImage.assetNetwork(
                    placeholder: Assets.imageTransparent,
                    image: incomingCallUser.photoURL!,
                    fit: BoxFit.cover,
                  ),
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
        if (currentUserData?.friendRequestsUids.isNotEmpty ?? false)
          _TitleAndContent(
            title: 'Friend requests',
            child: SizedBox(
              width: double.infinity,
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 32),
                itemCount: currentUserData?.friendRequestsUids.length,
                itemBuilder: (_, index) {
                  final uid = currentUserData!.friendRequestsUids[index];
                  return _FriendRequestListItem(key: ValueKey(uid), uid: uid);
                },
              ),
            ),
          ),
        Expanded(
          child: _TitleAndContent(
            title: 'Friends',
            child: Expanded(
              child: currentUserData?.friendsUids.isNotEmpty ?? false
                  ? GridView.builder(
                      scrollDirection: Axis.vertical,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                      ),
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        // `56` - FAB height
                        // `kFloatingActionButtonMargin` - FAB margin
                        // `8` - Custom spacing
                        bottom: 56 + kFloatingActionButtonMargin + 8,
                      ),
                      itemCount: currentUserData?.friendsUids.length,
                      itemBuilder: (_, index) {
                        final uid = currentUserData!.friendsUids[index];
                        return _FriendGridItem(key: ValueKey(uid), uid: uid);
                      },
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: double.infinity),
                          Lottie.asset(Assets.animationFriends, width: 300),
                          Text(
                            'Your friends will show up here',
                            style: context.titleMedium,
                          ),
                        ],
                      ),
                    ),
            ),
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

class _TitleAndContent extends StatelessWidget {
  const _TitleAndContent({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Text(
            title,
            style: context.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _FriendGridItem extends ConsumerWidget {
  const _FriendGridItem({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserDataProvider).valueOrNull;
    final friend = ref.watch(userProvider(uid: uid)).valueOrNull;
    final friendUpdater = ref.watch(friendshipStateProvider(uid: uid).notifier);

    if (friend == null || currentUser == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              color: friend.photoURL == null
                  ? context.theme.colorScheme.primaryContainer
                  : null,
              width: double.infinity,
              height: double.infinity,
              child: friend.photoURL == null
                  ? null
                  : FadeInImage.assetNetwork(
                      placeholder: Assets.imageTransparent,
                      image: friend.photoURL!,
                      fit: BoxFit.cover,
                    ),
            ),
            if (friend.photoURL != null)
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      context.theme.colorScheme.surfaceContainer,
                    ],
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    friend.name ?? '',
                    style: context.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      shadows: [
                        const Shadow(
                          blurRadius: 8,
                          color: Colors.black,
                          offset: Offset(-3, 3),
                        ),
                      ],
                    ),
                    maxLines: 3,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Confirm Call'),
                            content: Text(
                              'Do you want to start a call with ${friend.name}?',
                            ),
                            actions: [
                              FilledButton(
                                onPressed: () {
                                  dialogContext.pop<void>();
                                  Future.delayed(
                                    500.milliseconds,
                                    () => _joinCall(
                                      context: context,
                                      callerId: currentUser.uid,
                                      calleeId: friend.uid,
                                    ),
                                  );
                                },
                                child: const Text('Yes'),
                              ),
                              TextButton(
                                onPressed: dialogContext.pop<void>,
                                child: const Text('No'),
                              ),
                            ],
                          ),
                        ),
                        color: Colors.white,
                        icon: const Icon(Icons.videocam_outlined),
                        style: IconButton.styleFrom(
                          backgroundColor: context.theme.colorScheme.primary,
                          foregroundColor: context.theme.colorScheme.onPrimary,
                        ),
                      ),
                      IconButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Confirm Unfriend'),
                            content: Text(
                              'Are you sure you want to remove ${friend.name} from your friends list?',
                            ),
                            actions: [
                              FilledButton(
                                onPressed: () {
                                  dialogContext.pop<void>();
                                  Future.delayed(
                                    500.milliseconds,
                                    () => friendUpdater.unfriend(uid: uid),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: dialogContext
                                      .theme.colorScheme.errorContainer,
                                  foregroundColor: dialogContext
                                      .theme.colorScheme.onErrorContainer,
                                ),
                                child: const Text('Yes'),
                              ),
                              TextButton(
                                onPressed: dialogContext.pop<void>,
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      dialogContext.theme.colorScheme.onSurface,
                                ),
                                child: const Text('No'),
                              ),
                            ],
                          ),
                        ),
                        icon: const Icon(Icons.person_remove_outlined),
                        style: IconButton.styleFrom(
                          backgroundColor:
                              context.theme.colorScheme.errorContainer,
                          foregroundColor:
                              context.theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendRequestListItem extends ConsumerWidget {
  const _FriendRequestListItem({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserDataProvider).valueOrNull;
    final friend = ref.watch(userProvider(uid: uid)).valueOrNull;
    final friendUpdater = ref.watch(friendshipStateProvider(uid: uid).notifier);

    if (friend == null || currentUser == null) {
      return const SizedBox.shrink();
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: friend.photoURL != null
                ? FadeInImage.assetNetwork(
                    placeholder: Assets.imageTransparent,
                    image: friend.photoURL!,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: context.theme.colorScheme.primaryContainer,
                  ),
          ),
          if (friend.photoURL != null)
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    context.theme.colorScheme.surfaceContainer,
                  ],
                ),
              ),
            ),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  friend.name ?? '',
                  style: context.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    shadows: [
                      const Shadow(
                        blurRadius: 8,
                        color: Colors.black,
                        offset: Offset(-3, 3),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('wants to become your friend'),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.filled(
                      onPressed: () => friendUpdater.acceptFriendRequest(
                        uid: uid,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            context.theme.colorScheme.primaryContainer,
                        foregroundColor:
                            context.theme.colorScheme.onPrimaryContainer,
                      ),
                      icon: const Icon(Icons.check),
                      tooltip: 'Accept friend request',
                    ),
                    IconButton.filled(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Confirm Rejection'),
                          content: Text(
                            'Are you sure you want to reject ${friend.name}\'s friend request?',
                          ),
                          actions: [
                            FilledButton(
                              onPressed: () {
                                dialogContext.pop<void>();
                                friendUpdater.rejectFriendRequest(uid: uid);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: dialogContext
                                    .theme.colorScheme.errorContainer,
                                foregroundColor: dialogContext
                                    .theme.colorScheme.onErrorContainer,
                              ),
                              child: const Text('Yes'),
                            ),
                            TextButton(
                              onPressed: dialogContext.pop<void>,
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    dialogContext.theme.colorScheme.onSurface,
                              ),
                              child: const Text('No'),
                            ),
                          ],
                        ),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            context.theme.colorScheme.errorContainer,
                        foregroundColor:
                            context.theme.colorScheme.onErrorContainer,
                      ),
                      icon: const Icon(Icons.close),
                      tooltip: 'Reject friend request',
                    ),
                  ],
                ),
              ),
            ],
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
