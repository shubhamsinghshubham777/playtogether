import 'package:package_info_plus/package_info_plus.dart';
import 'package:playtogether/diagnostics.dart';

abstract final class AppVersion {
  static String? current;

  static String? get label => current == null ? null : 'v${current!}';

  static Future<void> load() async {
    try {
      current = (await PackageInfo.fromPlatform()).version;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the running app version');
    }
  }
}
