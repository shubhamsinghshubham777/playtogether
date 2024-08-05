import 'package:firebase_core/firebase_core.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/dashboard/view/dashboard_screen.dart';
import 'package:playtogether/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:playtogether/features/auth/view/auth_screen.dart';
import 'package:playtogether/utils.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (isDesktop) await _setupDesktopWindow();
  await _setupFirebase();
  runApp(const ProviderScope(child: PTApp()));
}

Future<void> _setupFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) {
    final host = isDesktop ? 'localhost' : '10.0.2.2';
    debugPrint('Firebase DEBUG host is: $host');
    FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseStorage.instance.useStorageEmulator(host, 9199);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  }
}

Future<void> _setupDesktopWindow() async {
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1000, 1000),
    minimumSize: Size(400, 800),
    center: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, windowManager.show);
}

class PTApp extends ConsumerStatefulWidget {
  const PTApp({super.key});

  @override
  ConsumerState<PTApp> createState() => _PTAppState();
}

class _PTAppState extends ConsumerState<PTApp> {
  bool? isLoggedIn;

  @override
  void initState() {
    postFrameCallBack(() async {
      final userId = await ref.read(currentUserIdProvider.future);
      setState(() => isLoggedIn = userId != null);
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: ThemeMode.dark,
      darkTheme: FlexThemeData.dark(
        scheme: FlexScheme.greenM3,
        useMaterial3: true,
        useMaterial3ErrorColors: true,
      ),
      debugShowCheckedModeBanner: false,
      home: isLoggedIn != null
          ? Scaffold(
              body: isLoggedIn == true
                  ? const DashboardScreen()
                  : const AuthScreen(),
            )
          : null,
    );
  }
}
