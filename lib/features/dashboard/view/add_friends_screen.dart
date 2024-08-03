import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';
import 'package:playtogether/features/dashboard/provider/friend_provider.dart';

class AddFriendsScreen extends ConsumerStatefulWidget {
  const AddFriendsScreen({super.key});

  @override
  ConsumerState<AddFriendsScreen> createState() => _AddFriendsScreenState();
}

class _AddFriendsScreenState extends ConsumerState<AddFriendsScreen> {
  final nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final searchFriendResultState = ref.watch(searchFriendResultProvider);
    final friendSearcher = ref.watch(searchFriendResultProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Friend'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter friend\'s name here',
                    ),
                    inputFormatters: [_CapitaliseFormatter()],
                  ),
                ),
                const SizedBox(width: 16),
                IconButton.filled(
                  onPressed: () => friendSearcher.searchFriendsByName(
                    nameController.text,
                  ),
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
        ),
      ),
      body: searchFriendResultState.when(
        data: (searchResult) {
          return ListView.builder(
            itemCount: searchResult.length,
            itemBuilder: (_, index) {
              final friend = searchResult[index];
              return _FriendListTile(key: ValueKey(friend.uid), friend: friend);
            },
          );
        },
        error: (e, st) => const Center(
          child: Text('Unexpected error occurred! Please try again later.'),
        ),
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
      ),
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
      leading: friend.photoURL != null
          ? Image.network(friend.photoURL!, width: 32, height: 32)
          : null,
      title: friend.name != null ? Text(friend.name!) : null,
      subtitle: friend.email != null ? Text(friend.email!) : null,
      trailing: IconButton(
        onPressed: switch (friendshipState) {
          FriendshipStatus.notFriend => () async {
              await friendshipNotifier.sendFriendRequest();
              if (context.mounted) {
                context.showSnackBar(
                  message: 'Friend request sent to ${friend.name}',
                );
              }
            },
          _ => null,
        },
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
