import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/firebase_options.dart';
import 'package:window_manager/window_manager.dart';

bool isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

void postFrameCallBack(VoidCallback callback) {
  WidgetsBinding.instance.addPostFrameCallback((_) => callback());
}

T callback<T>(T Function() callback) => callback();

List<Widget> verticalSpace(double space, List<Widget> children) {
  final widgets = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    widgets.add(
      Padding(
        padding: EdgeInsets.only(bottom: i != children.length ? space : 0),
        child: children[i],
      ),
    );
  }
  return widgets;
}

enum AppFlavor { development, production }

Future<void> initialiseApp(AppFlavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Setup desktop window
  if (isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1000, 1000),
      minimumSize: Size(400, 800),
      center: true,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, windowManager.show);
  }

  // Setup Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (flavor == AppFlavor.development) {
    final host = isDesktop ? 'localhost' : '10.0.2.2';
    FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseStorage.instance.useStorageEmulator(host, 9199);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  }
}
