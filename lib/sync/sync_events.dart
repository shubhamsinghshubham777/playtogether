/// Event type constants for broadcast messages
abstract class SyncEventType {
  static const String play = 'play';
  static const String pause = 'pause';
  static const String seek = 'seek';
  static const String stateRequest = 'state_request';
  static const String stateResponse = 'state_response';
  static const String chat = 'chat';
  static const String typing = 'typing';
}

/// Base class for all sync events
sealed class SyncEvent {
  final String senderId;
  final int timestamp;

  const SyncEvent({required this.senderId, required this.timestamp});

  Map<String, dynamic> toPayload();

  static SyncEvent? fromPayload(String event, Map<String, dynamic> payload) {
    return switch (event) {
      SyncEventType.play => PlayEvent.fromPayload(payload),
      SyncEventType.pause => PauseEvent.fromPayload(payload),
      SyncEventType.seek => SeekEvent.fromPayload(payload),
      SyncEventType.stateRequest => StateRequestEvent.fromPayload(payload),
      SyncEventType.stateResponse => StateResponseEvent.fromPayload(payload),
      _ => null,
    };
  }
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
  Map<String, dynamic> toPayload() => {
        'senderId': senderId,
        'timestamp': timestamp,
      };
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
  Map<String, dynamic> toPayload() => {
        'senderId': senderId,
        'timestamp': timestamp,
      };
}

class SeekEvent extends SyncEvent {
  final int positionMs;

  const SeekEvent({
    required super.senderId,
    required super.timestamp,
    required this.positionMs,
  });

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
  Map<String, dynamic> toPayload() => {
        'senderId': senderId,
        'timestamp': timestamp,
      };
}

class StateResponseEvent extends SyncEvent {
  final bool playing;
  final int positionMs;

  const StateResponseEvent({
    required super.senderId,
    required super.timestamp,
    required this.playing,
    required this.positionMs,
  });

  factory StateResponseEvent.fromPayload(Map<String, dynamic> payload) {
    return StateResponseEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      playing: payload['playing'] as bool,
      positionMs: payload['positionMs'] as int,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
        'senderId': senderId,
        'timestamp': timestamp,
        'playing': playing,
        'positionMs': positionMs,
      };
}

class ChatEvent extends SyncEvent {
  final String username;
  final String message;

  const ChatEvent({
    required super.senderId,
    required super.timestamp,
    required this.username,
    required this.message,
  });

  factory ChatEvent.fromPayload(Map<String, dynamic> payload) {
    return ChatEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      username: payload['username'] as String,
      message: payload['message'] as String,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
        'senderId': senderId,
        'timestamp': timestamp,
        'username': username,
        'message': message,
      };
}

class TypingEvent extends SyncEvent {
  final String username;
  final bool isTyping;

  const TypingEvent({
    required super.senderId,
    required super.timestamp,
    required this.username,
    required this.isTyping,
  });

  factory TypingEvent.fromPayload(Map<String, dynamic> payload) {
    return TypingEvent(
      senderId: payload['senderId'] as String,
      timestamp: payload['timestamp'] as int,
      username: payload['username'] as String,
      isTyping: payload['isTyping'] as bool,
    );
  }

  @override
  Map<String, dynamic> toPayload() => {
        'senderId': senderId,
        'timestamp': timestamp,
        'username': username,
        'isTyping': isTyping,
      };
}
