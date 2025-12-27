import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  static final supabaseUrl = dotenv.get("SUPABASE_URL");
  static final supabasePublishableKey = dotenv.get("SUPABASE_PUBLISHABLE_KEY");
}
