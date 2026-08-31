import 'package:flutter/foundation.dart';

const _desktopPlatforms = {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux};

/// True on the three desktop targets. Gates window_manager (OS-window
/// fullscreen) and any other desktop-only chrome.
bool get isDesktop => !kIsWeb && _desktopPlatforms.contains(defaultTargetPlatform);

/// True when built with `--dart-define=STORE_BUILD=true` (e.g. for Microsoft Store).
/// In-app updates must be disabled for store distributions because the store
/// manages background updates directly.
const isStoreBuild = bool.fromEnvironment('STORE_BUILD', defaultValue: false);

const _selfUpdatePlatforms = {TargetPlatform.macOS, TargetPlatform.windows};

bool get supportsSelfUpdate =>
    !kIsWeb && !isStoreBuild && _selfUpdatePlatforms.contains(defaultTargetPlatform);
