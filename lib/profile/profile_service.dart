import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_models.dart';

class ProfileService extends ChangeNotifier {
  ProfileService._();
  static final instance = ProfileService._();

  SupabaseClient get _client => Supabase.instance.client;

  Profile? _profile;
  Profile? get profile => _profile;

  Future<Profile?> load() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      _profile = null;
      notifyListeners();
      return null;
    }
    // The signup trigger creates the row; retry briefly for a brand-new user
    // whose trigger hasn't committed yet.
    for (var attempt = 0; attempt < 3; attempt++) {
      final row = await _client.from('profiles').select().eq('id', uid).maybeSingle();
      if (row != null) {
        _profile = Profile.fromJson(row);
        notifyListeners();
        return _profile;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return null;
  }

  void clear() {
    _profile = null;
    notifyListeners();
  }

  @visibleForTesting
  void setProfileForTesting(Profile? p) {
    _profile = p;
    notifyListeners();
  }

  Future<void> updateDisplayName(String name) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('profiles').update({'display_name': name.trim()}).eq('id', uid);
    _profile = _profile?.copyWith(displayName: name.trim());
    notifyListeners();
  }

  /// Downscales/crops to a centered 512×512 JPEG and uploads to
  /// `avatars/<uid>.jpg`; stores a cache-busted public URL on the profile.
  Future<void> uploadAvatar(Uint8List bytes) async {
    final uid = _client.auth.currentUser!.id;

    final jpeg = await compute(_processAvatar, bytes);
    await _client.storage
        .from('avatars')
        .uploadBinary(
          '$uid.jpg',
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );

    final publicUrl = _client.storage.from('avatars').getPublicUrl('$uid.jpg');
    final busted = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    await _client.from('profiles').update({'avatar_url': busted}).eq('id', uid);
    _profile = _profile?.copyWith(avatarUrl: busted);
    notifyListeners();
  }
}

Uint8List _processAvatar(Uint8List bytes) {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('unsupported_image');
  }
  decoded = img.bakeOrientation(decoded);
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final cropped = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final resized = img.copyResize(
    cropped,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.cubic,
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}
