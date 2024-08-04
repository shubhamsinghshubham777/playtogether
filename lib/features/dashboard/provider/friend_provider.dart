import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'friend_provider.g.dart';

@riverpod
class User extends _$User {
  @override
  Stream<PTUser?> build({required String? uid}) async* {
    if (uid != null) {
      yield* FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .map((docSnapshot) {
        final rawData = docSnapshot.data();
        if (rawData != null) return PTUser.fromJson(rawData);
        return null;
      });
    }
  }

  Future<void> updateUser(PTUser? user) async {
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(user.toJson());
    }
  }
}

@riverpod
class SearchFriendResult extends _$SearchFriendResult {
  @override
  AsyncValue<List<PTUser>> build() => const AsyncData([]);

  Future<void> searchFriendsByName(String friendName) async {
    if (friendName.isEmpty) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final currentUserData = await ref.read(currentUserDataProvider.future);
      if (currentUserData != null) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(
              'name',
              isGreaterThanOrEqualTo: friendName,
              isLessThanOrEqualTo: '$friendName\uf7ff',
              isNotEqualTo: currentUserData.name,
            )
            .get();
        return querySnapshot.docs
            .map((docSnapshot) => PTUser.fromJson(docSnapshot.data()))
            .toList();
      } else {
        return [];
      }
    });
  }
}

@riverpod
class FriendshipState extends _$FriendshipState {
  @override
  FriendshipStatus build({required String uid}) {
    final currentUserData = ref.watch(currentUserDataProvider).valueOrNull;
    final friendData = ref.watch(userProvider(uid: uid)).valueOrNull;

    if (currentUserData == null || friendData == null) {
      return FriendshipStatus.unknown;
    }

    final isAlreadyAFriend = currentUserData.friendsUids.contains(uid);

    final haveReceivedRequest =
        currentUserData.friendRequestsUids.contains(uid);

    final haveSentRequest =
        friendData.friendRequestsUids.contains(currentUserData.uid);

    if (isAlreadyAFriend) return FriendshipStatus.friend;
    if (haveReceivedRequest) return FriendshipStatus.requestReceived;
    if (haveSentRequest) return FriendshipStatus.requestSent;
    return FriendshipStatus.notFriend;
  }

  Future<void> sendFriendRequest() async {
    final currentUserData = await ref.read(currentUserDataProvider.future);
    final friendData = await ref.read(userProvider(uid: uid).future);

    final isRequestAlreadySent =
        friendData?.friendRequestsUids.contains(currentUserData?.uid) ?? false;

    final isAlreadyFriend =
        friendData?.friendsUids.contains(currentUserData?.uid) ?? false;

    if (isRequestAlreadySent) {
      throw Exception(
        'A friend request was already sent to this user. Please wait for them to respond.',
      );
    }

    if (isAlreadyFriend) {
      throw Exception(
        'Cannot send friend request to a user who is already your friend!',
      );
    }

    if (currentUserData != null && friendData != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
            friendData
                .copyWith(
                  friendRequestsUids:
                      friendData.friendRequestsUids + [currentUserData.uid],
                )
                .toJson(),
          );
    }
  }

  /// Someone sent you a friend request, therefore his uid should be available
  /// in your `friendRequestsUids` array. You just need to move it from
  /// `friendRequestsUids` to `friendsUids` array to make him a friend of yours
  /// and subsequently add your uid to his `friendsUids` array to make you a
  /// friend of his.
  Future<void> acceptFriendRequest({required String uid}) async {
    final currentUserData = await ref.read(currentUserDataProvider.future);
    final friendData = await ref.read(userProvider(uid: uid).future);
    final currentUserUpdater = ref.read(currentUserDataProvider.notifier);
    final friendUpdater = ref.read(userProvider(uid: uid).notifier);

    if (currentUserData != null && friendData != null) {
      final currentUserFriendsUids = currentUserData.friendsUids.toList();

      final currentUserFriendRequestsUids =
          currentUserData.friendRequestsUids.toList();

      final friendFriendUids = friendData.friendsUids.toList();

      currentUserFriendsUids.add(uid);
      currentUserFriendRequestsUids.remove(uid);
      friendFriendUids.add(currentUserData.uid);

      await Future.wait([
        currentUserUpdater.updateUserData(
          currentUserData.copyWith(
            friendsUids: currentUserFriendsUids,
            friendRequestsUids: currentUserFriendRequestsUids,
          ),
        ),
        friendUpdater.updateUser(
          friendData.copyWith(friendsUids: friendFriendUids),
        )
      ]);
    }
  }

  /// Someone sent you a friend request, therefore his uid should be available
  /// in your `friendRequestsUids` array. You just need to remove it from
  /// `friendRequestsUids` array to reject his friend request.
  Future<void> rejectFriendRequest({required String uid}) async {
    final currentUserData = await ref.read(currentUserDataProvider.future);
    final currentUserUpdater = ref.read(currentUserDataProvider.notifier);

    if (currentUserData != null) {
      final updatedFriendRequestsUids =
          currentUserData.friendRequestsUids.toList();

      updatedFriendRequestsUids.remove(uid);

      await currentUserUpdater.updateUserData(
        currentUserData.copyWith(friendRequestsUids: updatedFriendRequestsUids),
      );
    }
  }

  /// You already have a friend, meaning his uid is already added into your
  /// `friendsUids` and your uid is added into his `friendsUids` array.
  /// Therefore, to unfriend him, we need to remove your uid from his array
  /// and his uid from your array (basically the reverse of
  /// [acceptFriendRequest]).
  Future<void> unfriend({required String uid}) async {
    final currentUserData = await ref.read(currentUserDataProvider.future);
    final friendData = await ref.read(userProvider(uid: uid).future);
    final currentUserUpdater = ref.read(currentUserDataProvider.notifier);
    final friendUpdater = ref.read(userProvider(uid: uid).notifier);

    if (currentUserData != null && friendData != null) {
      final currentUserFriendsUids = currentUserData.friendsUids.toList();

      final friendFriendUids = friendData.friendsUids.toList();

      currentUserFriendsUids.remove(uid);
      friendFriendUids.remove(currentUserData.uid);

      await Future.wait([
        currentUserUpdater.updateUserData(
          currentUserData.copyWith(friendsUids: currentUserFriendsUids),
        ),
        friendUpdater.updateUser(
          friendData.copyWith(friendsUids: friendFriendUids),
        )
      ]);
    }
  }
}

enum FriendshipStatus {
  friend,
  notFriend,
  requestSent,
  requestReceived,
  unknown
}
