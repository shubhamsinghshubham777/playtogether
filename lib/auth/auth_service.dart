import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper over Supabase auth. Session persistence and token refresh are
/// handled by supabase_flutter; this only exposes the state the app reacts to.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  Session? get session => _client.auth.currentSession;
  User? get user => _client.auth.currentUser;
  bool get isSignedIn => session != null;
  bool get isGuest => user?.isAnonymous ?? false;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Browser OAuth + deep-link callback — the one flow that works on every
  /// platform (plan Phase 1). supabase_flutter handles the callback URI.
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'playtogether://auth-callback',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signInAsGuest({String? captchaToken}) async {
    await _client.auth.signInAnonymously(captchaToken: captchaToken);
  }

  /// Upgrades a guest to a Google account in place (same user id).
  Future<void> linkGoogleIdentity() async {
    await _client.auth.linkIdentity(
      OAuthProvider.google,
      redirectTo: 'playtogether://auth-callback',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthException catch (e) {
      // A revoked/expired session still means "signed out" locally.
      debugPrint('signOut: ${e.message}');
      await _client.auth.signOut(scope: SignOutScope.local);
    }
  }

  Future<void> deleteAccount() async {
    await _client.rpc('delete_account');
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}
