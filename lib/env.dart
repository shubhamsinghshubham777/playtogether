import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  /// Debug builds talk to the local Supabase stack when one is configured, so
  /// migrations, RPC changes and destructive testing never touch the project
  /// real users are on. Release builds always take the production values, and
  /// a debug build with no local stack configured falls back to them too.
  static String get supabaseUrl => _local("SUPABASE_URL_LOCAL") ?? dotenv.get("SUPABASE_URL");

  static String get supabasePublishableKey =>
      _local("SUPABASE_PUBLISHABLE_KEY_LOCAL") ?? dotenv.get("SUPABASE_PUBLISHABLE_KEY");

  /// True when this build is pointed at a local stack rather than production —
  /// surfaced in the lobby so a debug session can never be mistaken for one.
  static bool get usingLocalStack => kDebugMode && _local("SUPABASE_URL_LOCAL") != null;

  static String? _local(String key) {
    if (!kDebugMode) return null;
    final value = dotenv.maybeGet(key);
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Optional until LiveKit is configured; AV features are hidden without it.
  static final livekitUrl = dotenv.maybeGet("LIVEKIT_URL");

  /// Optional; when set, guest sign-in requires a Turnstile captcha token
  /// (the server enforces it — [auth.captcha] in supabase/config.toml).
  static final turnstileSiteKey = dotenv.maybeGet("TURNSTILE_SITE_KEY");

  /// Optional; error reporting is disabled entirely when absent, which is the
  /// normal state for local development. A Sentry DSN is a public write-only
  /// key, so shipping it in the bundle is fine — unlike a server secret.
  static final sentryDsn = dotenv.maybeGet("SENTRY_DSN");

  static final posthogApiKey = dotenv.maybeGet("POSTHOG_API_KEY");

  static final posthogHost = dotenv.maybeGet("POSTHOG_HOST");
}
