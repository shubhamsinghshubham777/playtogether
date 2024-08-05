import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/assets.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/dashboard/provider/friend_provider.dart';
import 'package:playtogether/features/dashboard/view/friends/friends_screen.dart';

class FriendRequestListItem extends ConsumerWidget {
  const FriendRequestListItem({super.key, required this.uid});

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
                    imageErrorBuilder: (_, __, ___) => networkImageErrorIcon,
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
