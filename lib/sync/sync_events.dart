/// Event type constants for broadcast messages
abstract class SyncEventType {
  static const String play = 'play';
  static const String pause = 'pause';
  static const String seek = 'seek';
  static const String stateRequest = 'state_request';
  static const String stateResponse = 'state_response';
  static const String modeSwitch = 'mode_switch';
  static const String chat = 'chat';
  static const String typing = 'typing';
  static const String positionSync = 'position_sync';
  static const String fileInfo = 'file_info';
  static const String mediaSet = 'media_set';
  static const String memberKicked = 'member_kicked';
  static const String transportLock = 'transport_lock';
  static const String reaction = 'reaction';
  static const String roomEnded = 'room_ended';
  static const String gateWaiver = 'gate_waiver';
  static const String uploadProgress = 'upload_progress';
  static const String sharingToggled = 'sharing_toggled';
  static const String roomExtended = 'room_extended';
}

/// Why a play/pause happened. Absent means a human pressed something — the
/// distinction attribution toasts and gate auto-resume both hang off.
abstract class SyncActionReason {
  static const String gate = 'gate';

  /// The positional realignment that rides along with a play/pause. It keeps
  /// everyone at the same spot but is not a seek anyone performed, so it must
  /// not be attributed as one.
  static const String transport = 'transport';
}

/// Base class for all sync events. `senderId` is the authenticated user id.
sealed class SyncEvent {
  final String senderId;
  final int timestamp;

  const SyncEvent({required this.senderId, required this.timestamp});

  Map<String, dynamic> toPayload();
}

class PlayEvent extends SyncEvent {
  /// [SyncActionReason] when the gate derived this rather than a human; null
  /// for a real button press.
  final String? reason;

  /// Whose readiness the gate was waiting on, for the banner copy.
  final String? subjectUserId;

  const PlayEvent({
    required super.senderId,
    required super.timestamp,
    this.reason,
    this.subjectUserId,
  });

  factory PlayEvent.fromPayload(Map<String, dynamic> payload) {
    return PlayEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      reason: payload['reason'] as String?,
      subjectUserId: payload['subjectUserId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'reason': reason,
    'subjectUserId': subjectUserId,
  };
}

class PauseEvent extends SyncEvent {
  final String? reason;
  final String? subjectUserId;

  const PauseEvent({
    required super.senderId,
    required super.timestamp,
    this.reason,
    this.subjectUserId,
  });

  factory PauseEvent.fromPayload(Map<String, dynamic> payload) {
    return PauseEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      reason: payload['reason'] as String?,
      subjectUserId: payload['subjectUserId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'reason': reason,
    'subjectUserId': subjectUserId,
  };
}

class SeekEvent extends SyncEvent {
  final int positionMs;

  /// [SyncActionReason] when this seek is mechanical rather than a jump a
  /// human made; null for a real scrub.
  final String? reason;

  const SeekEvent({
    required super.senderId,
    required super.timestamp,
    required this.positionMs,
    this.reason,
  });

  factory SeekEvent.fromPayload(Map<String, dynamic> payload) {
    return SeekEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      positionMs: payload['positionMs'] as int,
      reason: payload['reason'] as String?,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'positionMs': positionMs,
    'reason': reason,
  };
}

class StateRequestEvent extends SyncEvent {
  const StateRequestEvent({required super.senderId, required super.timestamp});

  factory StateRequestEvent.fromPayload(Map<String, dynamic> payload) {
    return StateRequestEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {'senderId': senderId, 'timestamp': timestamp};
}

class StateResponseEvent extends SyncEvent {
  final bool playing;
  final int positionMs;
  final String mode;
  final String? youtubeUrl;
  final String? fileName;
  final int? fileDurationMs;

  const StateResponseEvent({
    required super.senderId,
    required super.timestamp,
    required this.playing,
    required this.positionMs,
    required this.mode,
    this.youtubeUrl,
    this.fileName,
    this.fileDurationMs,
  });

  factory StateResponseEvent.fromPayload(Map<String, dynamic> payload) {
    return StateResponseEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      playing: payload['playing'] as bool,
      positionMs: payload['positionMs'] as int,
      mode: payload['mode'] as String? ?? 'local',
      youtubeUrl: payload['youtubeUrl'] as String?,
      fileName: payload['fileName'] as String?,
      fileDurationMs: payload['fileDurationMs'] as int?,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'playing': playing,
    'positionMs': positionMs,
    'mode': mode,
    'youtubeUrl': youtubeUrl,
    'fileName': fileName,
    'fileDurationMs': fileDurationMs,
  };
}

class ModeSwitchEvent extends SyncEvent {
  final String mode;
  final String? youtubeUrl;

  const ModeSwitchEvent({
    required super.senderId,
    required super.timestamp,
    required this.mode,
    this.youtubeUrl,
  });

  factory ModeSwitchEvent.fromPayload(Map<String, dynamic> payload) {
    return ModeSwitchEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      mode: payload['mode'] as String,
      youtubeUrl: payload['youtubeUrl'] as String?,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'mode': mode,
    'youtubeUrl': youtubeUrl,
  };
}

class ChatEvent extends SyncEvent {
  final String displayName;
  final String message;

  const ChatEvent({
    required super.senderId,
    required super.timestamp,
    required this.displayName,
    required this.message,
  });

  factory ChatEvent.fromPayload(Map<String, dynamic> payload) {
    return ChatEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      displayName: payload['displayName'] as String,
      message: payload['message'] as String,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'displayName': displayName,
    'message': message,
  };
}

class TypingEvent extends SyncEvent {
  final String displayName;
  final bool isTyping;

  const TypingEvent({
    required super.senderId,
    required super.timestamp,
    required this.displayName,
    required this.isTyping,
  });

  factory TypingEvent.fromPayload(Map<String, dynamic> payload) {
    return TypingEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      displayName: payload['displayName'] as String,
      isTyping: payload['isTyping'] as bool,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'displayName': displayName,
    'isTyping': isTyping,
  };
}

/// Host heartbeat while playing: members correct only if drift > 1.5 s.
class PositionSyncEvent extends SyncEvent {
  final int positionMs;
  final bool playing;

  const PositionSyncEvent({
    required super.senderId,
    required super.timestamp,
    required this.positionMs,
    required this.playing,
  });

  factory PositionSyncEvent.fromPayload(Map<String, dynamic> payload) {
    return PositionSyncEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      positionMs: payload['positionMs'] as int,
      playing: payload['playing'] as bool,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'positionMs': positionMs,
    'playing': playing,
  };
}

/// The room's canonical media, fanned out by the host straight after
/// `set_room_media` persisted it. The `rooms` row stays the source of truth —
/// this is latency, not durability, since clients also refetch on join and on
/// every reconnect.
class MediaSetEvent extends SyncEvent {
  final String kind;
  final String? name;
  final int? durationMs;
  final String? url;

  /// `rooms.media_updated_at` — the **server** clock, not the sender's. It is
  /// the ordering key that lets a room-row refetch resolving late be discarded
  /// instead of clobbering this event.
  final int? updatedAtMs;

  const MediaSetEvent({
    required super.senderId,
    required super.timestamp,
    required this.kind,
    this.name,
    this.durationMs,
    this.url,
    this.updatedAtMs,
  });

  factory MediaSetEvent.fromPayload(Map<String, dynamic> payload) {
    return MediaSetEvent(
      // Tolerant: neither field is read when this is applied, so a payload
      // missing them must still deliver the media rather than throw.
      senderId: payload['senderId'] as String? ?? '',
      timestamp: payload['timestamp'] as int? ?? 0,
      kind: payload['kind'] as String? ?? 'none',
      name: payload['name'] as String?,
      durationMs: payload['durationMs'] as int?,
      url: payload['url'] as String?,
      updatedAtMs: payload['updatedAtMs'] as int?,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'kind': kind,
    'name': name,
    'durationMs': durationMs,
    'url': url,
    'updatedAtMs': updatedAtMs,
  };
}

class ReactionEvent extends SyncEvent {
  final String emoji;
  final String displayName;

  const ReactionEvent({
    required super.senderId,
    required super.timestamp,
    required this.emoji,
    required this.displayName,
  });

  factory ReactionEvent.fromPayload(Map<String, dynamic> payload) {
    return ReactionEvent(
      senderId: payload['senderId'] as String? ?? '',
      timestamp: payload['timestamp'] as int? ?? 0,
      emoji: payload['emoji'] as String? ?? '',
      displayName: payload['displayName'] as String? ?? 'Watcher',
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'emoji': emoji,
    'displayName': displayName,
  };
}

/// Local-file identity (name + duration) so mismatched files get a banner.
class FileInfoEvent extends SyncEvent {
  final String fileName;
  final int durationMs;

  const FileInfoEvent({
    required super.senderId,
    required super.timestamp,
    required this.fileName,
    required this.durationMs,
  });

  factory FileInfoEvent.fromPayload(Map<String, dynamic> payload) {
    return FileInfoEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      fileName: payload['fileName'] as String,
      durationMs: payload['durationMs'] as int,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'fileName': fileName,
    'durationMs': durationMs,
  };
}

class UploadProgressEvent extends SyncEvent {
  final double fraction;
  final double speedBps;
  final int etaSeconds;
  final String state;

  const UploadProgressEvent({
    required super.senderId,
    required super.timestamp,
    required this.fraction,
    required this.speedBps,
    required this.etaSeconds,
    required this.state,
  });

  factory UploadProgressEvent.fromPayload(Map<String, dynamic> payload) {
    return UploadProgressEvent(
      senderId: payload['senderId'] as String? ?? '',
      timestamp: payload['timestamp'] as int? ?? 0,
      fraction: (payload['fraction'] as num?)?.toDouble() ?? 0.0,
      speedBps: (payload['speedBps'] as num?)?.toDouble() ?? 0.0,
      etaSeconds: (payload['etaSeconds'] as num?)?.toInt() ?? 0,
      state: payload['state'] as String? ?? 'uploading',
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'fraction': fraction,
    'speedBps': speedBps,
    'etaSeconds': etaSeconds,
    'state': state,
  };
}

class SharingToggledEvent extends SyncEvent {
  final bool enabled;
  final String? fileName;
  final int? fileSize;
  final String? uploadState;

  const SharingToggledEvent({
    required super.senderId,
    required super.timestamp,
    required this.enabled,
    this.fileName,
    this.fileSize,
    this.uploadState,
  });

  factory SharingToggledEvent.fromPayload(Map<String, dynamic> payload) {
    return SharingToggledEvent(
      senderId: payload['senderId'] as String? ?? '',
      timestamp: payload['timestamp'] as int? ?? 0,
      enabled: payload['enabled'] as bool? ?? false,
      fileName: payload['fileName'] as String?,
      fileSize: (payload['fileSize'] as num?)?.toInt(),
      uploadState: payload['uploadState'] as String?,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'enabled': enabled,
    'fileName': fileName,
    'fileSize': fileSize,
    'uploadState': uploadState,
  };
}

class RoomExtendedEvent extends SyncEvent {
  final String expiresAt;
  final int durationMinutes;

  const RoomExtendedEvent({
    required super.senderId,
    required super.timestamp,
    required this.expiresAt,
    required this.durationMinutes,
  });

  factory RoomExtendedEvent.fromPayload(Map<String, dynamic> payload) {
    return RoomExtendedEvent(
      senderId: payload['senderId'] as String? ?? '',
      timestamp: payload['timestamp'] as int? ?? 0,
      expiresAt: payload['expiresAt'] as String? ?? '',
      durationMinutes: (payload['durationMinutes'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'expiresAt': expiresAt,
    'durationMinutes': durationMinutes,
  };
}
