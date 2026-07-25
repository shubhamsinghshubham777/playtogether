import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  static final supabaseUrl = dotenv.get("SUPABASE_URL");
  static final supabasePublishableKey = dotenv.get("SUPABASE_PUBLISHABLE_KEY");

  /// Optional until LiveKit is configured; AV features are hidden without it.
  static final livekitUrl = dotenv.maybeGet("LIVEKIT_URL");

  /// Optional; when set, guest sign-in requires a Turnstile captcha token
  /// (the server enforces it — [auth.captcha] in supabase/config.toml).
  static final turnstileSiteKey = dotenv.maybeGet("TURNSTILE_SITE_KEY");
}
