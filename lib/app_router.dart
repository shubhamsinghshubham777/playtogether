import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'profile/entitlement_service.dart';
import 'profile/profile_screen.dart';
import 'profile/profile_service.dart';
import 'profile/subscription_screen.dart';
import 'rooms/lobby_screen.dart';
import 'rooms/room_screen.dart';
import 'rooms/room_service.dart';
import 'ui/pt_motion.dart';

/// Profile, subscribe and rooms are *sub-routes* of the lobby, so the lobby is always the
/// page beneath them in the navigator stack. That is what makes `go('/lobby')`
/// — every back button, leave, eviction and end-room exit — shrink the stack
/// and play the reverse (pop) transition. As sibling top-level routes, `go`
/// swaps the whole stack and Flutter animates it as a forward push instead.
const kRoomPathPrefix = '/lobby/room/';

String roomPath(String roomId) => '$kRoomPathPrefix$roomId';

/// Room id of the currently shown location, or null when not in a room.
String? roomIdOfPath(String path) =>
    path.startsWith(kRoomPathPrefix) ? path.substring(kRoomPathPrefix.length) : null;

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
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadeThrough(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/lobby',
        pageBuilder: (context, state) => _fadeThrough(state, const LobbyScreen()),
        routes: [
          GoRoute(
            path: 'profile',
            pageBuilder: (context, state) => _sharedAxis(state, const ProfileScreen()),
          ),
          GoRoute(
            path: 'subscribe',
            pageBuilder: (context, state) => _sharedAxis(
              state,
              SubscriptionScreen(source: state.uri.queryParameters['source']),
            ),
          ),
          GoRoute(
            path: 'room/:id',
            // Keyed by room id: go_router reuses the page for room A → room B
            // (same route pattern), and without the key the old room's State —
            // sync channel, countdown, chat — would survive the navigation.
            pageBuilder: (context, state) => _rise(
              state,
              RoomScreen(
                key: ValueKey(state.pathParameters['id']!),
                roomId: state.pathParameters['id']!,
                player: player,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Every transition is fade-dominant and short. The room mounts a media_kit
/// texture and (in YouTube mode) a platform-view WebView, and heavy transforms
/// over those jank — so the translate legs stay small and nothing scales.
///
/// `key: state.pageKey` is not optional: it is what makes go_router treat a
/// re-navigation to the same location as the same page rather than a new one.
CustomTransitionPage<void> _page(
  GoRouterState state,
  Widget child,
  RouteTransitionsBuilder transitions,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: PTMotion.page,
    reverseTransitionDuration: PTMotion.page,
    transitionsBuilder: transitions,
  );
}

/// Auth swaps the whole world, so login ⇄ lobby reads as a scene change rather
/// than navigation: no directional slide at all.
CustomTransitionPage<void> _fadeThrough(GoRouterState state, Widget child) {
  return _page(state, child, (context, animation, secondary, child) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: PTMotion.enter),
      child: child,
    );
  });
}

/// Entering the theater: the room rises into place, and sinks back down on
/// every `go('/lobby')` exit — leave, eviction, end-room — because the nested
/// lobby→room stack makes those genuine pops.
CustomTransitionPage<void> _rise(GoRouterState state, Widget child) {
  return _page(state, child, (context, animation, secondary, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: PTMotion.enter,
      reverseCurve: PTMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  });
}

/// Sibling detail page — a subtle horizontal shared axis.
CustomTransitionPage<void> _sharedAxis(GoRouterState state, Widget child) {
  return _page(state, child, (context, animation, secondary, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: PTMotion.enter,
      reverseCurve: PTMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  });
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
          EntitlementService.instance.load();
        case AuthChangeEvent.signedOut:
          ProfileService.instance.clear();
          EntitlementService.instance.clear();
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
