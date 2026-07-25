class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.isGuest,
    this.email,
    this.avatarUrl,
    this.createdAt,
  });

  final String id;
  final String displayName;
  final bool isGuest;
  final String? email;
  final String? avatarUrl;
  final DateTime? createdAt;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      isGuest: json['is_guest'] as bool,
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Profile copyWith({String? displayName, String? avatarUrl}) {
    return Profile(
      id: id,
      displayName: displayName ?? this.displayName,
      isGuest: isGuest,
      email: email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
    );
  }
}
