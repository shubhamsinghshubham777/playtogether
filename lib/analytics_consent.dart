import 'package:flutter/foundation.dart';
import 'package:synctogether/analytics.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOptOutKey = 'pt.analytics_opted_out';

class AnalyticsConsent extends ChangeNotifier {
  AnalyticsConsent._();
  static final instance = AnalyticsConsent._();

  bool _optedOut = false;
  bool get optedOut => _optedOut;

  Future<bool> load() async {
    try {
      _optedOut = (await SharedPreferences.getInstance()).getBool(_kOptOutKey) ?? false;
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the analytics opt-out preference');
    }
    return _optedOut;
  }

  Future<void> setOptedOut(bool value) async {
    if (_optedOut == value) return;
    _optedOut = value;
    Analytics.instance.setOptedOut(value);
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_kOptOutKey, value);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'saving the analytics opt-out preference');
    }
  }
}
