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
  static const String roomEnded = 'room_ended';
}

/// Base class for all sync events. `senderId` is the authenticated user id.
sealed class SyncEvent {
  final String senderId;
  final int timestamp;

  const SyncEvent({required this.senderId, required this.timestamp});

  Map<String, dynamic> toPayload();
}

class PlayEvent extends SyncEvent {
  const PlayEvent({required super.senderId, required super.timestamp});

  factory PlayEvent.fromPayload(Map<String, dynamic> payload) {
    return PlayEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {'senderId': senderId, 'timestamp': timestamp};
}

class PauseEvent extends SyncEvent {
  const PauseEvent({required super.senderId, required super.timestamp});

  factory PauseEvent.fromPayload(Map<String, dynamic> payload) {
    return PauseEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {'senderId': senderId, 'timestamp': timestamp};
}

class SeekEvent extends SyncEvent {
  final int positionMs;

  const SeekEvent({required super.senderId, required super.timestamp, required this.positionMs});

  factory SeekEvent.fromPayload(Map<String, dynamic> payload) {
    return SeekEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      positionMs: payload['positionMs'] as int,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
    'senderId': senderId,
    'timestamp': timestamp,
    'positionMs': positionMs,
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
