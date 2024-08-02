import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'friend_provider.g.dart';

@riverpod
Stream<PTUser?> user(UserRef ref, {required String? uid}) async* {
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
