import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/env.dart';

const _prod = '''
SUPABASE_URL=https://prod.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_prod
''';

const _withLocal =
    '''
$_prod
SUPABASE_URL_LOCAL=http://127.0.0.1:54321
SUPABASE_PUBLISHABLE_KEY_LOCAL=sb_publishable_local
''';

void main() {
  test('flutter test runs in debug, which is what this file is about', () {
    expect(kDebugMode, isTrue);
  });

  test('a debug build prefers the local stack when one is configured', () {
    dotenv.loadFromString(envString: _withLocal);
    expect(Env.supabaseUrl, 'http://127.0.0.1:54321');
    expect(Env.supabasePublishableKey, 'sb_publishable_local');
    expect(Env.usingLocalStack, isTrue);
  });

  test('a debug build with no local stack falls back to production', () {
    dotenv.loadFromString(envString: _prod);
    expect(Env.supabaseUrl, 'https://prod.supabase.co');
    expect(Env.supabasePublishableKey, 'sb_publishable_prod');
    expect(Env.usingLocalStack, isFalse);
  });

  test('an empty local value is treated as absent, not as an empty url', () {
    dotenv.loadFromString(
      envString:
          '''
$_prod
SUPABASE_URL_LOCAL=
SUPABASE_PUBLISHABLE_KEY_LOCAL=
''',
    );
    expect(Env.supabaseUrl, 'https://prod.supabase.co');
    expect(Env.usingLocalStack, isFalse);
  });

  test('the local key is only honoured alongside a local url', () {
    dotenv.loadFromString(
      envString:
          '''
$_prod
SUPABASE_PUBLISHABLE_KEY_LOCAL=sb_publishable_local
''',
    );
    expect(Env.supabaseUrl, 'https://prod.supabase.co');
    expect(
      Env.usingLocalStack,
      isFalse,
      reason: 'a key without a url must not read as a local session',
    );
  });
}
