import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'sync_events.dart';

class SyncService {
  static const String _roomName = 'playtogether:default';

  final Player _player;
  final String _clientId = const Uuid().v4();
  final String username;

  RealtimeChannel? _channel;
  int _lastAppliedTimestamp = 0;
  bool _hasReceivedInitialState = false;
  bool _isApplyingRemoteAction = false;

  final _chatController = StreamController<ChatEvent>.broadcast();
  Stream<ChatEvent> get chatMessages => _chatController.stream;

  final _peerOnlineController = StreamController<bool>.broadcast();
  Stream<bool> get peerOnlineStream => _peerOnlineController.stream;
  bool _isPeerOnline = false;
  bool get isPeerOnline => _isPeerOnline;

  final _typingController = StreamController<TypingEvent>.broadcast();
  Stream<TypingEvent> get typingStream => _typingController.stream;

  final _modeSwitchController = StreamController<ModeSwitchEvent>.broadcast();
  Stream<ModeSwitchEvent> get modeSwitchStream => _modeSwitchController.stream;

  final _chatHistory = <ChatEvent>[];
  List<ChatEvent> get chatHistory => List.unmodifiable(_chatHistory);

  // Callbacks for dual-player control (local vs YouTube)
  void Function()? onRemotePlay;
  void Function()? onRemotePause;
  void Function(Duration)? onRemoteSeek;

  // Track current playback state
  String _currentMode = 'local';
  String? _currentYoutubeUrl;

  SyncService(this._player, {required this.username});

  /// Connect to the sync channel and start listening
  Future<void> connect() async {
    final supabase = Supabase.instance.client;

    _channel = supabase.channel(_roomName, opts: const RealtimeChannelConfig(self: false));

    _channel!
        .onBroadcast(event: SyncEventType.play, callback: _handlePlay)
        .onBroadcast(event: SyncEventType.pause, callback: _handlePause)
        .onBroadcast(event: SyncEventType.seek, callback: _handleSeek)
        .onBroadcast(event: SyncEventType.stateRequest, callback: _handleStateRequest)
        .onBroadcast(event: SyncEventType.stateResponse, callback: _handleStateResponse)
        .onBroadcast(event: SyncEventType.modeSwitch, callback: _handleModeSwitch)
        .onBroadcast(event: SyncEventType.chat, callback: _handleChat)
        .onBroadcast(event: SyncEventType.typing, callback: _handleTyping)
        .onPresenceSync(_handlePresenceSync)
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _requestInitialState();
            _channel?.track({'clientId': _clientId, 'username': username});
          }
        });
  }

  void _handlePresenceSync(RealtimePresenceSyncPayload payload) {
    final presences = _channel?.presenceState();
    if (presences == null) return;
    // Count other users (exclude self)
    int otherUserCount = 0;
    for (final presence in presences) {
      for (final p in presence.presences) {
        if (p.payload['clientId'] != _clientId) {
          otherUserCount++;
        }
      }
    }
    final isOnline = otherUserCount > 0;
    if (_isPeerOnline != isOnline) {
      _isPeerOnline = isOnline;
      _peerOnlineController.add(isOnline);
    }
  }

  /// Broadcast a chat message and store it in history
  Future<ChatEvent> broadcastChat(String message) async {
    final event = ChatEvent(
      senderId: _clientId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: username,
      message: message,
    );
    _chatHistory.add(event);
    await _channel?.sendBroadcastMessage(event: SyncEventType.chat, payload: event.toPayload());
    return event;
  }

  void _handleChat(Map<String, dynamic> payload) {
    final event = ChatEvent.fromPayload(payload);
    _chatHistory.add(event);
    _chatController.add(event);
  }

  /// Broadcast typing status
  Future<void> broadcastTyping(bool isTyping) async {
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.typing,
      payload: TypingEvent(
        senderId: _clientId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: username,
        isTyping: isTyping,
      ).toPayload(),
    );
  }

  void _handleTyping(Map<String, dynamic> payload) {
    final event = TypingEvent.fromPayload(payload);
    _typingController.add(event);
  }

  /// Broadcast a play action
  Future<void> broadcastPlay() async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.play,
      payload: PlayEvent(
        senderId: _clientId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ).toPayload(),
    );
  }

  /// Broadcast a pause action
  Future<void> broadcastPause() async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.pause,
      payload: PauseEvent(
        senderId: _clientId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ).toPayload(),
    );
  }

  /// Broadcast a seek action
  Future<void> broadcastSeek(Duration position) async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.seek,
      payload: SeekEvent(
        senderId: _clientId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        positionMs: position.inMilliseconds,
      ).toPayload(),
    );
  }

  /// Broadcast a mode switch action
  Future<void> broadcastModeSwitch(String mode, String? youtubeUrl) async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.modeSwitch,
      payload: ModeSwitchEvent(
        senderId: _clientId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        mode: mode,
        youtubeUrl: youtubeUrl,
      ).toPayload(),
    );
  }

  /// Update the current playback state (called by PTVideoPlayer)
  void updatePlaybackState(String mode, String? youtubeUrl) {
    _currentMode = mode;
    _currentYoutubeUrl = youtubeUrl;
  }

  void _requestInitialState() {
    _channel?.sendBroadcastMessage(
      event: SyncEventType.stateRequest,
      payload: StateRequestEvent(
        senderId: _clientId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ).toPayload(),
    );
  }

  void _handlePlay(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    _applyRemoteAction(() {
      if (onRemotePlay != null) {
        onRemotePlay!();
      } else {
        _player.play();
      }
    });
  }

  void _handlePause(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    _applyRemoteAction(() {
      if (onRemotePause != null) {
        onRemotePause!();
      } else {
        _player.pause();
      }
    });
  }

  void _handleSeek(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    final positionMs = payload['positionMs'] as int;
    _applyRemoteAction(() {
      if (onRemoteSeek != null) {
        onRemoteSeek!(Duration(milliseconds: positionMs));
      } else {
        _player.seek(Duration(milliseconds: positionMs));
      }
    });
  }

  void _handleModeSwitch(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    final event = ModeSwitchEvent.fromPayload(payload);
    _modeSwitchController.add(event);
  }

  void _handleStateRequest(Map<String, dynamic> payload) {
    // Only respond if we have a video loaded (local mode) or YouTube URL set
    if (_player.state.duration == Duration.zero && _currentYoutubeUrl == null) return;

    _channel?.sendBroadcastMessage(
      event: SyncEventType.stateResponse,
      payload: StateResponseEvent(
        senderId: _clientId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        playing: _player.state.playing,
        positionMs: _player.state.position.inMilliseconds,
        mode: _currentMode,
        youtubeUrl: _currentYoutubeUrl,
      ).toPayload(),
    );
  }

  void _handleStateResponse(Map<String, dynamic> payload) {
    // Only apply first response
    if (_hasReceivedInitialState) return;
    _hasReceivedInitialState = true;

    final event = StateResponseEvent.fromPayload(payload);

    // First, handle mode switch if needed
    if (event.mode != 'local' || event.youtubeUrl != null) {
      final modeSwitchEvent = ModeSwitchEvent(
        senderId: event.senderId,
        timestamp: event.timestamp,
        mode: event.mode,
        youtubeUrl: event.youtubeUrl,
      );
      _modeSwitchController.add(modeSwitchEvent);
    }

    // Then apply playback state
    _applyRemoteAction(() async {
      await Future.delayed(const Duration(milliseconds: 500)); // Wait for mode switch to complete
      if (onRemoteSeek != null) {
        onRemoteSeek!(Duration(milliseconds: event.positionMs));
      } else {
        await _player.seek(Duration(milliseconds: event.positionMs));
      }
      if (event.playing) {
        if (onRemotePlay != null) {
          onRemotePlay!();
        } else {
          await _player.play();
        }
      } else {
        if (onRemotePause != null) {
          onRemotePause!();
        } else {
          await _player.pause();
        }
      }
    });
  }

  bool _shouldApply(Map<String, dynamic> payload) {
    final senderId = payload['senderId'] as String;
    final timestamp = payload['timestamp'] as int;

    // Skip if this is our own message (shouldn't happen with self:false, but safety check)
    if (senderId == _clientId) return false;

    // Skip if we've already applied a more recent action (last-action-wins)
    if (timestamp <= _lastAppliedTimestamp) return false;

    _lastAppliedTimestamp = timestamp;
    return true;
  }

  void _applyRemoteAction(dynamic Function() action) {
    _isApplyingRemoteAction = true;
    action();
    // Reset flag after a short delay to allow player state to settle
    Future.delayed(const Duration(milliseconds: 100), () {
      _isApplyingRemoteAction = false;
    });
  }

  Future<void> disconnect() async {
    await _channel?.unsubscribe();
    _channel = null;
  }

  void dispose() {
    _chatController.close();
    _peerOnlineController.close();
    _typingController.close();
    _modeSwitchController.close();
    disconnect();
  }
}
