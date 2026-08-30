import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:synctogether/diagnostics.dart';

/// Windows-only preparation for the webviews in the app — the guest captcha and
/// the YouTube player embed, which share one environment.
///
/// Everywhere else the plugin's defaults are right and every member here stays
/// null/false, so callers can use them unconditionally.
abstract final class PTWebView {
  /// The environment [InAppWebView] should be created against, or null to let
  /// the plugin build its own (correct on every non-Windows platform, and the
  /// fallback if [init] could not improve on it).
  static WebViewEnvironment? environment;

  /// Set only when we positively know no WebView2 runtime is installed, which
  /// no amount of retrying will fix. An environment that merely failed to
  /// *create* leaves this false — see [init].
  static bool runtimeMissing = false;

  /// Separates the two Windows-only ways the captcha webview fails to appear,
  /// because they need completely different fixes and look identical on screen.
  ///
  /// The runtime can genuinely be absent — LTSC/Server and de-bloated images —
  /// which is what the installer's Evergreen bootstrapper is for, and
  /// `getAvailableVersion` is how we learn it did not take.
  ///
  /// More often the runtime is present and the *environment* still fails. With
  /// no `userDataFolder` set, WebView2 defaults it to the directory holding the
  /// executable and tries to create `synctogether.exe.WebView2` next to it. The
  /// installer is an admin install, so that directory is under Program Files, a
  /// standard user token cannot write there, and creation fails with nothing on
  /// the wire but "Cannot create the InAppWebView instance!". That is what a
  /// Windows 11 machine reported against 0.5.2 — where the runtime ships in-box
  /// and the bootstrapper correctly had nothing to do. Pointing the folder at
  /// LOCALAPPDATA is Microsoft's documented fix for packaged apps.
  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      final version = await WebViewEnvironment.getAvailableVersion();
      if (version == null) {
        runtimeMissing = true;
        reportNonFatal(
          StateError('No WebView2 runtime is installed'),
          StackTrace.current,
          during: 'preparing the Windows webview runtime',
        );
        return;
      }
      final folder = await _userDataFolder();
      environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: folder,
          additionalBrowserArguments: '--autoplay-policy=no-user-gesture-required',
        ),
      );
      trace(
        'webview2 ready',
        category: 'webview',
        data: {'version': version, 'userDataFolder': folder},
      );
    } catch (e, s) {
      // Deliberately not treated as fatal for the dialog: whatever stopped us
      // building a better environment may not stop the plugin building its
      // own, and attempting the challenge beats refusing it outright. The
      // report is what makes the difference visible if it does fail later.
      reportNonFatal(e, s, during: 'preparing the Windows webview runtime');
    }
  }

  /// Creating the directory here rather than leaving it to WebView2 is the
  /// point of the exercise: a permissions problem then surfaces as a Dart
  /// exception naming the path, instead of an opaque native failure.
  static Future<String> _userDataFolder() async {
    final base = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['TEMP'];
    if (base == null || base.isEmpty) {
      throw StateError('Neither LOCALAPPDATA nor TEMP is set');
    }
    final dir = Directory('$base\\SyncTogether\\WebView2');
    await dir.create(recursive: true);
    return dir.path;
  }
}
