import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/app_router.dart';
import 'package:playtogether/auth/auth_service.dart';
import 'package:playtogether/env.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/rooms/room_service.dart';
import 'package:playtogether/ui/pt_theme.dart';
import 'package:playtogether/ui/responsive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  MediaKit.ensureInitialized();
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
  }

  /// playtogether://join/<code> — invite links. The auth callback URI is
  /// consumed by supabase_flutter before it reaches this stream.
  Future<void> _onDeepLink(Uri uri) async {
    if (uri.scheme != 'playtogether' || uri.host != 'join') return;
    final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (code == null || code.isEmpty) return;

    if (!AuthService.instance.isSignedIn) {
      // Parked; the lobby picks it up right after login/guest entry.
      RoomService.instance.pendingJoinCode = code;
      router.go('/login');
      return;
    }
    try {
      final room = await RoomService.instance.joinRoom(code);
      router.go('/room/${room.id}');
    } catch (e) {
      final message = RoomErrorCode.fromError(e).message;
      _scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
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
      builder: buildResponsiveWrapper,
    );
  }
}
