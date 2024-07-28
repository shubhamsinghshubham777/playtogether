import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'GOOGLE_CLIENT_ID')
  static String googleClientId = _Env.googleClientId;

  @EnviedField(varName: 'GOOGLE_CLIENT_SECRET')
  static String googleClientSecret = _Env.googleClientSecret;
}
