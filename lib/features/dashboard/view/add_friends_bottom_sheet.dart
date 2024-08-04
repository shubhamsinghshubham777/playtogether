import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:playtogether/assets.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';
import 'package:playtogether/features/dashboard/provider/friend_provider.dart';

class AddFriendsBottomSheet extends ConsumerStatefulWidget {
  const AddFriendsBottomSheet({super.key});

  @override
  ConsumerState<AddFriendsBottomSheet> createState() =>
      _AddFriendsBottomSheetState();
}

class _AddFriendsBottomSheetState extends ConsumerState<AddFriendsBottomSheet> {
  final nameController = TextEditingController();
  final textFieldFocusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    final searchFriendResultState = ref.watch(searchFriendResultProvider);
    final friendSearcher = ref.watch(searchFriendResultProvider.notifier);

    return Column(
      children: [
        Text('Add Friends', style: context.titleLarge),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    hintText: 'Enter friend\'s name',
                    suffixIconConstraints: const BoxConstraints(maxWidth: 64),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        onPressed: () {
                          nameController.clear();
                          friendSearcher.searchFriendsByName('');
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                  focusNode: textFieldFocusNode,
                  inputFormatters: [_CapitaliseFormatter()],
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.search,
                  onSubmitted: friendSearcher.searchFriendsByName,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () {
                  textFieldFocusNode.unfocus();
                  friendSearcher.searchFriendsByName(nameController.text);
                },
                icon: const Icon(Icons.search),
                tooltip: 'Search for friend',
              ),
            ],
          ),
        ),
        Expanded(
          child: searchFriendResultState.when(
            data: (searchResult) {
              if (searchResult.isEmpty) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          'Your friends will show up here',
                          style: context.titleMedium,
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -24),
                        child: Lottie.asset(
                          Assets.animationFriends,
                          width: 300,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: searchResult.length,
                itemBuilder: (_, index) {
                  final friend = searchResult[index];
                  return _FriendListTile(
                    key: ValueKey(friend.uid),
                    friend: friend,
                  );
                },
              );
            },
            error: (e, st) => const Center(
              child: Text('Unexpected error occurred! Please try again later.'),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }
}

class _FriendListTile extends ConsumerWidget {
  const _FriendListTile({super.key, required this.friend});

  final PTUser friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendshipState = ref.watch(
      friendshipStateProvider(uid: friend.uid),
    );
    final friendshipNotifier = ref.watch(
      friendshipStateProvider(uid: friend.uid).notifier,
    );

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 24, top: 8, right: 32),
      leading: friend.photoURL != null
          ? AvatarImage(backgroundImage: NetworkImage(friend.photoURL!))
          : null,
      title: friend.name != null
          ? Text(
              friend.name!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      subtitle: friend.email != null
          ? Text(
              friend.email!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: IconButton.outlined(
        onPressed: friendshipState == FriendshipStatus.notFriend
            ? friendshipNotifier.sendFriendRequest
            : null,
        icon: Icon(
          switch (friendshipState) {
            FriendshipStatus.friend => Icons.handshake,
            FriendshipStatus.notFriend => Icons.person_add,
            FriendshipStatus.requestSent => Icons.how_to_reg,
            FriendshipStatus.requestReceived => Icons.call_received,
            FriendshipStatus.unknown => Icons.device_unknown,
          },
        ),
      ),
    );
  }
}

class _CapitaliseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
