import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:synctogether/platform.dart';
import 'package:window_manager/window_manager.dart';

final GlobalKey storeCaptureBoundaryKey = GlobalKey();

Future<void> captureBoundaryToFile(String path, {double pixelRatio = 1.0}) async {
  final boundary =
      storeCaptureBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    // ignore: avoid_print
    print('[CAPTURE ERROR] RenderRepaintBoundary not found for key');
    return;
  }
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    // ignore: avoid_print
    print('[CAPTURE ERROR] Failed to encode PNG');
    return;
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(byteData.buffer.asUint8List());
  // ignore: avoid_print
  print('[STORE CAPTURE SUCCESS] Wrote $path (${file.lengthSync()} bytes)');
}

Future<void> runStoreCaptureFlow(BuildContext context, GoRouter router) async {
  // ignore: avoid_print
  print('[STORE CAPTURE] Starting automated store capture flow...');

  if (isDesktop) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1920, 1080));
      await windowManager.center();
    } catch (_) {}
  }

  // 1. Capture Lobby Screen
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 1: Capturing Lobby Screen...');
  router.go('/lobby');
  await Future.delayed(const Duration(milliseconds: 2500));
  await captureBoundaryToFile('assets/store/1_violet_glass_lobby.png');

  // 2. Capture Room Theater View
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 2: Capturing Room Theater View...');
  router.go('/lobby/room/demo-room-1');
  await Future.delayed(const Duration(milliseconds: 3000));
  await captureBoundaryToFile('assets/store/2_theater_room.png');

  // 3. Capture Room with Live Chat Panel
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 3: Capturing Room with Live Chat...');
  router.go('/lobby/room/demo-room-1?chat=true');
  await Future.delayed(const Duration(milliseconds: 2500));
  await captureBoundaryToFile('assets/store/3_room_chat.png');

  // 4. Capture Media Source Chooser Dialog
  // ignore: avoid_print
  print('[STORE CAPTURE] Step 4: Capturing Media Chooser Dialog...');
  router.go('/lobby/room/demo-room-1?dialog=media');
  await Future.delayed(const Duration(milliseconds: 2500));
  await captureBoundaryToFile('assets/store/4_media_chooser.png');

  // ignore: avoid_print
  print('[STORE CAPTURE] Complete! All store screenshots generated in assets/store/');
  exit(0);
}
