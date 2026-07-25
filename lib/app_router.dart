import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'profile/profile_screen.dart';
import 'profile/profile_service.dart';
import 'rooms/lobby_screen.dart';
import 'rooms/room_screen.dart';
import 'rooms/room_service.dart';

GoRouter buildRouter(Player player) {
  return GoRouter(
    initialLocation: '/lobby',
    refreshListenable: _AuthRefresh(),
    redirect: (context, state) {
      final signedIn = AuthService.instance.isSignedIn;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin) return '/lobby';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/lobby', builder: (context, state) => const LobbyScreen()),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(
        path: '/room/:id',
        builder: (context, state) => RoomScreen(
          roomId: state.pathParameters['id']!,
          player: player,
        ),
      ),
    ],
  );
}

/// Re-runs router redirects on every auth event; also keeps the loaded
/// profile in step with the session (signedOut wipes it).
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    _sub = AuthService.instance.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          ProfileService.instance.load();
        case AuthChangeEvent.signedOut:
          ProfileService.instance.clear();
          RoomService.instance.clear();
        default:
          break;
      }
      notifyListeners();
    });
  }

  late final StreamSubscription _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
