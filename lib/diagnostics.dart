import 'package:flutter/foundation.dart';

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
