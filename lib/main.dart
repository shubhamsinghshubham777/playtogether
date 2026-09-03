import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/analytics_consent.dart';
import 'package:synctogether/app_router.dart';
import 'package:synctogether/app_version.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/auth/webview_runtime.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/mock/mock_dependencies.dart';
import 'package:synctogether/mock/store_capture.dart';
import 'package:synctogether/platform.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/tls.dart';
import 'package:synctogether/updates/update_service.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';
import 'package:synctogether/ui/splash_screen.dart';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

const bool kCaptureStore = bool.fromEnvironment('CAPTURE_STORE', defaultValue: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // Reporting is opt-in via SENTRY_DSN, so a checkout without one still runs.
  // Sentry installs its own FlutterError.onError, which is what makes every
  // existing reportNonFatal call site arrive here for free — see diagnostics.dart.
  final dsn = Env.sentryDsn;
  if (dsn == null || dsn.isEmpty) return _bootstrap();
  return SentryFlutter.init((options) {
    options.dsn = dsn;
    options.environment = kReleaseMode ? 'release' : 'debug';
    // Crash reports only. Tracing would multiply event volume for no benefit
    // here, and the free tier is the budget.
    options.tracesSampleRate = 0;
    options.debug = kDebugMode;
  }, appRunner: _bootstrap);
}

Future<void> _bootstrap() async {
  // Before anything opens a socket, so the very first Supabase call already has
  // the bundled roots — and, if it still fails, says which certificate it was
  // offered.
  await installTlsOverrides();
  MediaKit.ensureInitialized();
  // OS-window fullscreen (F key in a room) needs the manager ready up front.
  if (isDesktop) await windowManager.ensureInitialized();
  // Windows needs a WebView2 environment rooted somewhere writable before the
  // guest captcha can render; everywhere else this returns immediately.
  await PTWebView.init();
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabasePublishableKey);
  trace('supabase ready', category: 'auth', data: {'local_stack': Env.usingLocalStack});
  if (kDemoMode) {
    installMockDependencies();
  }
  await AppVersion.load();
  final optedOut = await AnalyticsConsent.instance.load();
  Analytics.instance.init(
    apiKey: Env.posthogApiKey,
    host: Env.posthogHost,
    distinctId: Supabase.instance.client.auth.currentUser?.id,
    context: {'platform': defaultTargetPlatform.name, 'app_version': AppVersion.current},
    optedOut: optedOut,
  );
  Analytics.instance.track('app_opened');
  // Must follow initialize (it reads Supabase.instance) and precede runApp, so
  // the auth stream has an error handler before the first deep link can land.
  AuthService.instance.start();
  runApp(const MainApp());
  if (isDesktop && !kDebugMode) unawaited(_enterFullScreen());
  if (supportsSelfUpdate) unawaited(UpdateService.instance.checkForUpdate());
}

/// Desktop starts in OS fullscreen — this is a media app, and the room screen's
/// F/Esc toggle stays the way back out.
///
/// It has to wait for a frame: asked before the engine has drawn, macOS's
/// `toggleFullScreen` on a window that has never rendered leaves the app with
/// no window at all (frontmost, zero AXWindows) rather than a fullscreen one.
/// Hence after runApp, and unawaited — nothing downstream may block on the
/// window's shape, least of all a window manager that refuses outright.
Future<void> _enterFullScreen() async {
  try {
    await WidgetsBinding.instance.endOfFrame;
    await windowManager.setFullScreen(true);
  } catch (e, s) {
    reportNonFatal(e, s, during: 'launch fullscreen');
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  // Created once for the whole app lifetime; the room screen attaches to it.
  late final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
  late final router = buildRouter(player);
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<String>? _authFailureSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The OAuth callback resolves inside supabase_flutter, long after the login
    // button's own error handling has finished — so a failure there has no
    // screen to report itself on. This is that screen.
    _authFailureSub = AuthService.instance.failures.listen(
      (message) => showPTSnackVia(_scaffoldMessengerKey.currentState, message, kind: .error),
    );
    _linkSub = _appLinks.uriLinkStream.listen((uri) => _onDeepLink(uri, source: 'stream'));
    // The native side replays the launch URL only to the FIRST stream
    // subscriber — which is supabase_flutter (it subscribes inside
    // Supabase.initialize, before runApp). Cold-start invite links must
    // therefore be fetched explicitly; getInitialLink keeps returning the
    // launch URL regardless of that replay.
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _onDeepLink(uri, source: 'cold_start');
    });
    if (kCaptureStore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        runStoreCaptureFlow(context, router);
      });
    }
  }

  String? _lastLinkHandled;
  DateTime _lastLinkHandledAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// synctogether://join/<code> — invite links. The auth callback URI also
  /// flows through this stream (it's a broadcast shared with supabase_flutter);
  /// the `join` host filter is what keeps it out of this handler.
  Future<void> _onDeepLink(Uri uri, {required String source}) async {
    if (uri.scheme != 'synctogether' || uri.host != 'join') return;
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
    trace('invite link received', category: 'deeplink', data: {'source': source});

    if (!AuthService.instance.isSignedIn) {
      // Parked; the lobby picks it up right after login/guest entry.
      trace('invite parked until sign-in', category: 'deeplink');
      RoomService.instance.pendingJoinCode = code;
      router.go('/login');
      return;
    }
    try {
      final room = await RoomService.instance.joinRoom(code, via: .deeplink);
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
      trace('joining from an invite link', category: 'deeplink', data: {'room_id': room.id});
      router.go(roomPath(room.id));
    } catch (e, s) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .unknown) reportNonFatal(e, s, during: 'joining a room from an invite link');
      showPTSnackVia(_scaffoldMessengerKey.currentState, failure.message, kind: .error);
    }
  }

  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(Analytics.instance.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    _authFailureSub?.cancel();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SyncTogether',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: buildPTTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      // The splash is an overlay inside the app, not a route: routing, auth
      // redirects and the deep-link handler above all keep running underneath
      // it, so an invite that arrives during the splash is not lost.
      builder: (context, child) => RepaintBoundary(
        key: storeCaptureBoundaryKey,
        child: buildResponsiveWrapper(context, PTSplash(child: child ?? const SizedBox.shrink())),
      ),
    );
  }
}
