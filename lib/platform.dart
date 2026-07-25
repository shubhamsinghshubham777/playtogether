import 'package:flutter/foundation.dart';

const _desktopPlatforms = {
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
};

/// True on the three desktop targets. Gates window_manager (OS-window
/// fullscreen) and any other desktop-only chrome.
bool get isDesktop => !kIsWeb && _desktopPlatforms.contains(defaultTargetPlatform);
