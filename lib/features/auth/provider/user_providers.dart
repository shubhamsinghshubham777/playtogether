import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'user_providers.g.dart';

@riverpod
FutureOr<PTUser?> user(UserRef ref, {required String? uid}) async {
  if (uid == null) return null;

  final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

  if (!userDoc.exists || userDoc.data() == null) return null;

  return PTUser.fromJson(userDoc.data()!);
}
