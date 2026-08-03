import 'package:playtogether/profile/profile_models.dart';

const kRoomDurationCapMinutes = 240;

/// What the room is watching. Room-level rather than per-member so it survives
/// host succession and reaches late joiners without replaying broadcasts.
enum RoomMediaKind {
  none,
  local,
  youtube;

  static RoomMediaKind fromWire(String? value) => switch (value) {
    'local' => .local,
    'youtube' => .youtube,
    _ => .none,
  };

  String get wire => name;
}

class Room {
  const Room({
    required this.id,
    required this.code,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    required this.durationMinutes,
    required this.expiresAt,
    this.endedAt,
    this.mediaKind = .none,
    this.mediaName,
    this.mediaDuration,
    this.mediaUrl,
    this.mediaUpdatedAt,
    this.transportLock = false,
  });

  final String id;
  final String code;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final int durationMinutes;
  final DateTime expiresAt;
  final DateTime? endedAt;

  /// Canonical media — set by the host only, via `set_room_media`.
  final RoomMediaKind mediaKind;

  /// Local mode: the exact basename the readiness gate matches on.
  final String? mediaName;

  /// Soft ±2 s warning only — never gating (see the initiative's non-goals).
  final Duration? mediaDuration;
  final String? mediaUrl;

  /// Bumped on every `set_room_media`. A room-row refetch can resolve *after* a
  /// newer `media_set` broadcast has already been applied, so compare this
  /// before adopting media state from either source.
  final DateTime? mediaUpdatedAt;

  /// "The host has the remote" — when true only the host may play/pause/seek.
  final bool transportLock;

  bool get hasMedia => mediaKind != .none;

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      durationMinutes: json['duration_minutes'] as int,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at'] as String) : null,
      mediaKind: RoomMediaKind.fromWire(json['media_kind'] as String?),
      mediaName: json['media_name'] as String?,
      mediaDuration: json['media_duration_ms'] != null
          ? Duration(milliseconds: (json['media_duration_ms'] as num).toInt())
          : null,
      mediaUrl: json['media_url'] as String?,
      mediaUpdatedAt: json['media_updated_at'] != null
          ? DateTime.parse(json['media_updated_at'] as String)
          : null,
      transportLock: json['transport_lock'] as bool? ?? false,
    );
  }

  String get inviteLink => 'playtogether://join/$code';
}

/// The room's canonical media, split out of [Room] so the sync layer can pass
/// it around without carrying expiry/membership concerns.
class RoomMedia {
  const RoomMedia({required this.kind, this.name, this.duration, this.url, this.updatedAt});

  factory RoomMedia.fromRoom(Room room) => RoomMedia(
    kind: room.mediaKind,
    name: room.mediaName,
    duration: room.mediaDuration,
    url: room.mediaUrl,
    updatedAt: room.mediaUpdatedAt,
  );

  static const none = RoomMedia(kind: .none);

  final RoomMediaKind kind;
  final String? name;
  final Duration? duration;
  final String? url;
  final DateTime? updatedAt;

  bool get isSet => kind != .none;

  /// A room-row refetch can resolve *after* a newer `media_set` broadcast has
  /// been applied, so media is adopted only when strictly newer. State with no
  /// timestamp never wins — that is the never-set case, which must not be able
  /// to wipe media that has been set.
  bool isNewerThan(RoomMedia other) {
    final mine = updatedAt;
    if (mine == null) return false;
    final theirs = other.updatedAt;
    return theirs == null || mine.isAfter(theirs);
  }
}

class RoomMember {
  const RoomMember({
    required this.roomId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.profile,
  });

  final String roomId;
  final String userId;
  final String role;
  final DateTime joinedAt;
  final Profile? profile;

  bool get isHost => role == 'host';
  String get displayName => profile?.displayName ?? 'Watcher';

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      profile: json['profiles'] != null
          ? Profile.fromJson(json['profiles'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Friendly-copy mapping for RPC errors (design voice — no raw codes).
enum RoomErrorCode {
  roomNotFound('room_not_found', "Hmm, we couldn't find a room with that code."),
  roomEnded('room_ended', 'That room has already ended.'),
  roomFull('room_full', 'This room is full — 8 watchers max.'),
  roomBanned('room_banned', "The host removed you from this room, so you can't rejoin."),
  guestRoomLimit('guest_room_limit', 'Guests can host one live room at a time.'),
  notHost('not_host', 'Only the host can do that.'),
  cannotKickSelf('cannot_kick_self', "You can't remove yourself — leave the room instead."),
  invalidDuration('invalid_duration', 'Pick a duration between 5 minutes and 4 hours.'),
  invalidMedia('invalid_media', "Hmm, we couldn't set that as the room's video."),
  unknown('unknown', "Something went sideways. Give it another try.");

  const RoomErrorCode(this.code, this.message);

  final String code;
  final String message;

  static RoomErrorCode fromError(Object error) {
    final text = error.toString();
    for (final value in values) {
      if (text.contains(value.code)) return value;
    }
    return unknown;
  }
}
