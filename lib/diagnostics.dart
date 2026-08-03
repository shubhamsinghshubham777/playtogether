import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Reports a failure the app deliberately recovers from, without changing any
/// control flow.
///
/// Use it wherever a `catch` would otherwise be empty **and the failure has
/// consequences a user or a developer would want to know about** — a stranded
/// room membership, a chat line that never reached the database, canonical
/// media left stale. Routing through [FlutterError] means these land in the
/// error console with the same framing as any other Flutter error, show up in
/// DevTools, and still print in release via `debugPrint`.
///
/// Deliberately *not* for expected outcomes. A 10 s duration probe timing out,
/// a polled JS eval firing before the iframe exists, a `Uri` decode hitting a
/// stray `%` — those are the documented normal path, and reporting them is the
/// noise that trains people to stop reading logs.
///
/// When `SENTRY_DSN` is configured these also reach Sentry, because Sentry
/// installs its own `FlutterError.onError` during init — nothing here needs to
/// know about it.
void reportNonFatal(Object error, StackTrace? stack, {required String during}) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'playtogether',
      context: ErrorDescription(during),
    ),
  );
}

/// Records a step on a flow we expect to have to debug from a machine we do not
/// have — a Windows release build, say — so that whatever error eventually
/// arrives comes with the sequence that led to it attached.
///
/// Breadcrumbs are buffered and only transmitted alongside a captured event, so
/// a flow that succeeds costs nothing and sends nothing. That is the whole
/// reason to prefer these over [reportNonFatal] for routine steps: they are
/// free until something goes wrong. No-ops when reporting is not configured.
void trace(String message, {String? category, Map<String, dynamic>? data}) {
  if (kDebugMode) debugPrint('[$category] $message ${data ?? ''}');
  Sentry.addBreadcrumb(Breadcrumb(message: message, category: category, data: data));
}
