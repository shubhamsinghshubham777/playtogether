import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:playtogether/env.dart';
import 'package:playtogether/extensions.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_providers.g.dart';

@Riverpod(keepAlive: true)
class AuthenticatedUser extends _$AuthenticatedUser {
  GoogleSignIn get _googleClient => ref.read(googleClientProvider);

  @override
  Stream<PTUser?> build() {
    return FirebaseAuth.instance
        .userChanges()
        .map((firebaseUser) => firebaseUser?.toPTUser());
  }

  Future<void> signInWithGoogle() async {
    try {
      final googleResponse = await _googleClient.signIn();
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(
          idToken: googleResponse?.idToken,
          accessToken: googleResponse?.accessToken,
        ),
      );
    } catch (e, st) {
      debugPrint('error: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> signOut() async {
    await _googleClient.signOut();
    await FirebaseAuth.instance.signOut();
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
