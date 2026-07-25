import 'package:playtogether/profile/profile_models.dart';

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
  });

  final String id;
  final String code;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final int durationMinutes;
  final DateTime expiresAt;
  final DateTime? endedAt;

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
    );
  }

  String get inviteLink => 'playtogether://join/$code';
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
  guestRoomLimit('guest_room_limit', 'Guests can host one live room at a time.'),
  notHost('not_host', 'Only the host can do that.'),
  invalidDuration('invalid_duration', 'Pick a duration between 5 minutes and 4 hours.'),
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
