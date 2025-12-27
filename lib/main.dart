import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:playtogether/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  fvp.registerWith(
    options: {
      'subtitleFontFile':
          'https://github.com/mpv-android/mpv-android/raw/master/app/src/main/assets/subfont.ttf',
    },
  );
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabasePublishableKey);
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: .dark,
      home: Scaffold(body: Center(child: Text('Hello World!'))),
    );
  }
}
