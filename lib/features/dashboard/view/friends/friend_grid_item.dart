import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/assets.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/call/view/call_screen.dart';
import 'package:playtogether/features/dashboard/provider/friend_provider.dart';
import 'package:playtogether/features/dashboard/view/friends/friends_screen.dart';

class FriendGridItem extends ConsumerWidget {
  const FriendGridItem({
    super.key,
    required this.uid,
    required this.showControls,
  });

  final String uid;
  final bool showControls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserDataProvider).valueOrNull;
    final friend = ref.watch(userProvider(uid: uid)).valueOrNull;
    final friendUpdater = ref.watch(friendshipStateProvider(uid: uid).notifier);

    if (friend == null || currentUser == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(8),
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
                      imageErrorBuilder: (_, __, ___) => networkImageErrorIcon,
                      fit: BoxFit.cover,
                    ),
            ),
            if (friend.photoURL != null && showControls)
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
                if (showControls)
                  Padding(
                    padding: const EdgeInsets.all(8),
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
                                      () => context.push(
                                        CallScreen(
                                          callerUid: currentUser.uid,
                                          calleeUid: friend.uid,
                                          offer: null,
                                        ),
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
                            foregroundColor:
                                context.theme.colorScheme.onPrimary,
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
                                    foregroundColor: dialogContext
                                        .theme.colorScheme.onSurface,
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
