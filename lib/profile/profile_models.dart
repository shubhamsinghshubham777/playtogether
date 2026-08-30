class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.isGuest,
    this.email,
    this.avatarUrl,
    this.createdAt,
    this.freeExtensionUsed = false,
    this.r2UploadBytes7d = 0,
    this.r2UploadWindowStart,
    this.r2CooldownUntil,
  });

  final String id;
  final String displayName;
  final bool isGuest;
  final String? email;
  final String? avatarUrl;
  final DateTime? createdAt;

  final bool freeExtensionUsed;
  final int r2UploadBytes7d;
  final DateTime? r2UploadWindowStart;
  final DateTime? r2CooldownUntil;

  int remainingWeeklyBytes(int weeklyLimit) {
    if (r2UploadWindowStart == null) return weeklyLimit;
    final now = DateTime.now();
    if (now.difference(r2UploadWindowStart!).inDays >= 7) {
      return weeklyLimit;
    }
    return (weeklyLimit - r2UploadBytes7d).clamp(0, weeklyLimit);
  }

  Duration? get timeUntilQuotaReset {
    if (r2UploadWindowStart == null) return null;
    final resetAt = r2UploadWindowStart!.add(const Duration(days: 7));
    final diff = resetAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(count >= 10 || i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

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
      freeExtensionUsed: json['free_extension_used'] as bool? ?? false,
      r2UploadBytes7d: (json['r2_upload_bytes_7d'] as num?)?.toInt() ?? 0,
      r2UploadWindowStart: json['r2_upload_window_start'] != null
          ? DateTime.tryParse(json['r2_upload_window_start'] as String)
          : null,
      r2CooldownUntil: json['r2_cooldown_until'] != null
          ? DateTime.tryParse(json['r2_cooldown_until'] as String)
          : null,
    );
  }

  Profile copyWith({
    String? displayName,
    String? avatarUrl,
    bool? freeExtensionUsed,
    int? r2UploadBytes7d,
    DateTime? r2UploadWindowStart,
    DateTime? r2CooldownUntil,
  }) {
    return Profile(
      id: id,
      displayName: displayName ?? this.displayName,
      isGuest: isGuest,
      email: email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      freeExtensionUsed: freeExtensionUsed ?? this.freeExtensionUsed,
      r2UploadBytes7d: r2UploadBytes7d ?? this.r2UploadBytes7d,
      r2UploadWindowStart: r2UploadWindowStart ?? this.r2UploadWindowStart,
      r2CooldownUntil: r2CooldownUntil ?? this.r2CooldownUntil,
    );
  }
}
