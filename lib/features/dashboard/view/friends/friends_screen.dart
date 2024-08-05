import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:playtogether/assets.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/dashboard/provider/friend_provider.dart';
import 'package:playtogether/features/dashboard/view/friends/friend_grid_item.dart';
import 'package:playtogether/features/dashboard/view/friends/friend_request_list_item.dart';
import 'package:playtogether/features/dashboard/view/incoming_call_banner.dart';
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

    return SingleChildScrollView(
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: Durations.medium4,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => SizeTransition(
              sizeFactor: animation,
              child: child,
            ),
            child: incomingCallData != null && incomingCallUser != null
                ? IncomingCallBanner(
                    user: incomingCallUser,
                    data: incomingCallData,
                  )
                : null,
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
                    return FriendRequestListItem(key: ValueKey(uid), uid: uid);
                  },
                ),
              ),
            ),
          _TitleAndContent(
            title: 'Friends',
            child: currentUserData?.friendsUids.isNotEmpty ?? false
                ? GridView.builder(
                    scrollDirection: Axis.vertical,
                    physics: const NeverScrollableScrollPhysics(),
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
                      return FriendGridItem(
                        key: ValueKey(uid),
                        uid: uid,
                        showControls: uid != incomingCallUser?.uid,
                      );
                    },
                    shrinkWrap: true,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: double.infinity),
                      Text(
                        'Your friends will show up here',
                        style: context.titleMedium,
                      ),
                      Lottie.asset(Assets.animationFriends, width: 300),
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

const networkImageErrorIcon = Icon(Icons.error_outline, size: 100);
