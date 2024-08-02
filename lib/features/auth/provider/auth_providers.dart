import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:playtogether/env.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_providers.g.dart';

@riverpod
class CurrentUserId extends _$CurrentUserId {
  GoogleSignIn get _googleClient => ref.read(googleClientProvider);

  @override
  Stream<String?> build() {
    return FirebaseAuth.instance
        .userChanges()
        .map((firebaseUser) => firebaseUser?.uid);
  }

  Future<void> signInWithGoogle() async {
    try {
      final googleResponse = await _googleClient.signIn();
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(
          idToken: googleResponse?.idToken,
          accessToken: googleResponse?.accessToken,
        ),
      );
      await onboardUser(userCredential);
    } catch (e, st) {
      debugPrint('error: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> signOut() async {
    await _googleClient.signOut();
    await FirebaseAuth.instance.signOut();
  }

  Future<void> onboardUser(UserCredential userCredential) async {
    final docSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userCredential.user?.uid)
        .get();

    final user = userCredential.user;

    // Only onboard if the user is not already onboarded
    if (!docSnapshot.exists && user != null) {
      final ptUser = PTUser(
        uid: user.uid,
        name: user.displayName,
        email: user.email,
        photoURL: user.photoURL,
        friendsUids: [],
        friendRequestsUids: [],
      );

      FirebaseFirestore.instance
          .collection('users')
          .doc(ptUser.uid)
          .set(ptUser.toJson());
    }
  }
}

@Riverpod(keepAlive: true)
GoogleSignIn googleClient(GoogleClientRef ref) {
  return GoogleSignIn(
    params: GoogleSignInParams(
      clientId: Env.googleClientId,
      clientSecret: Env.googleClientSecret,
      redirectPort: 5000,
    ),
  );
}

@riverpod
Stream<PTUser?> currentUserData(CurrentUserDataRef ref) async* {
  final userId = ref.watch(currentUserIdProvider).valueOrNull;
  if (userId != null) {
    yield* FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((docSnapshot) {
      final rawData = docSnapshot.data();
      if (rawData != null) return PTUser.fromJson(rawData);
      return null;
    });
  }
}
