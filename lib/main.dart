import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/env.dart';
import 'package:playtogether/player/pt_video_player.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:playtogether/username_dialog.dart';
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
  SyncService? syncService;
  String? username;

  void _onUsernameSelected(String selectedUsername) {
    setState(() {
      username = selectedUsername;
      syncService = SyncService(player, username: selectedUsername);
    });
    syncService!.connect();
  }

  @override
  void dispose() {
    syncService?.dispose();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: .dark,
      home: Scaffold(
        body: syncService != null
            ? PTVideoPlayer(player, syncService!)
            : _UsernameSelectionScreen(onUsernameSelected: _onUsernameSelected),
      ),
    );
  }
}

class _UsernameSelectionScreen extends StatefulWidget {
  const _UsernameSelectionScreen({required this.onUsernameSelected});

  final ValueChanged<String> onUsernameSelected;

  @override
  State<_UsernameSelectionScreen> createState() => _UsernameSelectionScreenState();
}

class _UsernameSelectionScreenState extends State<_UsernameSelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDialog());
  }

  Future<void> _showDialog() async {
    final selectedUsername = await UsernameDialog.show(context);
    if (selectedUsername != null) {
      widget.onUsernameSelected(selectedUsername);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
