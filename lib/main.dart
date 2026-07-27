import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/app_router.dart';
import 'package:playtogether/auth/auth_service.dart';
import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/env.dart';
import 'package:playtogether/platform.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/rooms/room_service.dart';
import 'package:playtogether/ui/banners.dart';
import 'package:playtogether/ui/pt_theme.dart';
import 'package:playtogether/ui/responsive.dart';
import 'package:playtogether/ui/splash_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  MediaKit.ensureInitialized();
  // OS-window fullscreen (F key in a room) needs the manager ready up front.
  if (isDesktop) {
    await windowManager.ensureInitialized();
    // Hide the native title bar; window_manager still shows the window once
    // the style is applied, so `show`/`focus` here replace the default show.
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(titleBarStyle: TitleBarStyle.hidden),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabasePublishableKey);
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  // Created once for the whole app lifetime; the room screen attaches to it.
  late final player = Player();
  late final router = buildRouter(player);
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _linkSub = _appLinks.uriLinkStream.listen(_onDeepLink);
    // The native side replays the launch URL only to the FIRST stream
    // subscriber — which is supabase_flutter (it subscribes inside
    // Supabase.initialize, before runApp). Cold-start invite links must
    // therefore be fetched explicitly; getInitialLink keeps returning the
    // launch URL regardless of that replay.
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _onDeepLink(uri);
    });
  }

  String? _lastLinkHandled;
  DateTime _lastLinkHandledAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// playtogether://join/<code> — invite links. The auth callback URI also
  /// flows through this stream (it's a broadcast shared with supabase_flutter);
  /// the `join` host filter is what keeps it out of this handler.
  Future<void> _onDeepLink(Uri uri) async {
    if (uri.scheme != 'playtogether' || uri.host != 'join') return;
    final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (code == null || code.isEmpty) return;

    // A cold-start link can arrive via both getInitialLink and the stream.
    final now = DateTime.now();
    if (uri.toString() == _lastLinkHandled &&
        now.difference(_lastLinkHandledAt) < const Duration(seconds: 5)) {
      return;
    }
    _lastLinkHandled = uri.toString();
    _lastLinkHandledAt = now;

    if (!AuthService.instance.isSignedIn) {
      // Parked; the lobby picks it up right after login/guest entry.
      RoomService.instance.pendingJoinCode = code;
      router.go('/login');
      return;
    }
    try {
      final room = await RoomService.instance.joinRoom(code);
      // Invited into a different room while already in one: leave the old
      // room's membership, or it counts against caps and authority election.
      final currentId = roomIdOfPath(router.routerDelegate.currentConfiguration.uri.path);
      if (currentId != null && currentId.isNotEmpty && currentId != room.id) {
        try {
          await RoomService.instance.leaveRoom(currentId);
        } catch (e, s) {
          // Still navigate — the invite is what the user asked for. But the old
          // membership row survives, and it keeps counting against that room's
          // 8-member cap and its authority election until expiry.
          reportNonFatal(e, s, during: 'leaving room $currentId after an invite');
        }
      }
      router.go(roomPath(room.id));
    } catch (e) {
      showPTSnackVia(
        _scaffoldMessengerKey.currentState,
        RoomErrorCode.fromError(e).message,
        kind: .error,
      );
    }
  }

  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void dispose() {
    _linkSub?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PlayTogether',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: buildPTTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      // The splash is an overlay inside the app, not a route: routing, auth
      // redirects and the deep-link handler above all keep running underneath
      // it, so an invite that arrives during the splash is not lost.
      builder: (context, child) =>
          buildResponsiveWrapper(context, PTSplash(child: child ?? const SizedBox.shrink())),
    );
  }
}
