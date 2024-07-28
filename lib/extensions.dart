import 'package:firebase_auth/firebase_auth.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';

extension FirebaseUserX on User {
  PTUser toPTUser() {
    return PTUser(
      uid: uid,
      name: displayName ?? '',
      email: email ?? '',
      photoURL: photoURL,
    );
  }
}
