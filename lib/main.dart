import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/env.dart';
import 'package:playtogether/player/pt_video_player.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  MediaKit.ensureInitialized();
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabasePublishableKey);
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final player = Player();
  late final syncService = SyncService(player);

  @override
  void initState() {
    super.initState();
    syncService.connect();
  }

  @override
  void dispose() {
    syncService.dispose();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: .dark,
      home: Scaffold(body: PTVideoPlayer(player, syncService)),
    );
  }
}
