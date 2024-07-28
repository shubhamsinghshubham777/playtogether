import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

void postFrameCallBack(VoidCallback callback) {
  WidgetsBinding.instance.addPostFrameCallback((_) => callback());
}
