import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:playtogether/analytics.dart';
import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/platform.dart';
import 'package:playtogether/updates/appcast.dart';

const kAppcastUrl =
    'https://github.com/shubhamsinghshubham777/playtogether/releases/latest/download/appcast.xml';

const _kWinSparkleConfigKey = r'HKCU\Software\app.playtogether\playtogether\WinSparkle';

class UpdateService extends ChangeNotifier with UpdaterListener {
  UpdateService._();

  static final instance = UpdateService._();

  String? _availableVersion;
  String? get availableVersion => _availableVersion;

  String? _currentVersion;
  String? get currentVersion => _currentVersion;

  bool _dismissed = false;
  bool _handingOff = false;
  bool _nativeReady = false;

  bool get handingOff => _handingOff;

  bool get hasUpdate => _availableVersion != null && !_dismissed;

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    notifyListeners();
  }

  Future<void> checkForUpdate() async {
    if (!supportsSelfUpdate) return;
    String? current;
    try {
      current = (await PackageInfo.fromPlatform()).version;
      _currentVersion = current;
      final latest = await _fetchLatestVersion();
      if (latest == null) return;
      final newer = compareVersions(latest, current) > 0;
      trace(
        'update check finished',
        category: 'updates',
        data: {'current': current, 'latest': latest, 'newer': newer},
      );
      if (!newer) return;
      _availableVersion = latest;
      notifyListeners();
    } on SocketException catch (e) {
      trace('update check offline', category: 'updates', data: {'error': '$e'});
    } on HandshakeException catch (e) {
      trace('update check tls failure', category: 'updates', data: {'error': '$e'});
    } on TimeoutException catch (e) {
      trace('update check timed out', category: 'updates', data: {'error': '$e'});
    } catch (e, s) {
      reportNonFatal(e, s, during: 'checking for an app update (current $current)');
    }
  }

  Future<bool> installAndRestart() async {
    if (!supportsSelfUpdate || _handingOff) return false;
    _handingOff = true;
    notifyListeners();
    try {
      if (!_nativeReady) {
        if (Platform.isWindows) await _silenceWinSparkleOwnChecks();
        autoUpdater.addListener(this);
        await autoUpdater.setScheduledCheckInterval(0);
        await autoUpdater.setFeedURL(kAppcastUrl);
        _nativeReady = true;
      }
      trace(
        'handing off to the native updater',
        category: 'updates',
        data: {'from': _currentVersion, 'to': _availableVersion},
      );
      await autoUpdater.checkForUpdates();
      return true;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting the native updater');
      return false;
    } finally {
      _handingOff = false;
      notifyListeners();
    }
  }

  Future<String?> _fetchLatestVersion() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(kAppcastUrl));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException(
          'appcast fetch returned ${response.statusCode}',
          uri: Uri.parse(kAppcastUrl),
        );
      }
      final version = newestVersionIn(body);
      if (version == null) {
        throw const FormatException('appcast carried no recognisable version');
      }
      return version;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _silenceWinSparkleOwnChecks() async {
    try {
      final result = await Process.run('reg.exe', [
        'add',
        _kWinSparkleConfigKey,
        '/v',
        'CheckForUpdates',
        '/t',
        'REG_SZ',
        '/d',
        '0',
        '/f',
      ]);
      if (result.exitCode != 0) {
        throw ProcessException(
          'reg.exe',
          ['add', _kWinSparkleConfigKey],
          '${result.stderr}'.trim(),
          result.exitCode,
        );
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: "disabling WinSparkle's own update checks");
    }
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    reportNonFatal(
      error ?? UpdaterError('the native updater failed without a reason'),
      StackTrace.current,
      during: 'installing the update to $_availableVersion',
    );
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) =>
      trace('native updater checking', category: 'updates');

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) => trace(
    'native updater found an update',
    category: 'updates',
    data: {'version': appcastItem?.versionString},
  );

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) =>
      trace('native updater found nothing', category: 'updates', data: {'error': '$error'});

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) =>
      trace('native updater downloaded the update', category: 'updates');

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    trace('quitting for the update installer', category: 'updates');
    final flushed = Analytics.instance.flush().timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    if (Platform.isWindows) flushed.whenComplete(() => exit(0));
  }
}
