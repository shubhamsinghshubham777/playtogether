import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'sync_events.dart';

class SyncService {
  static const String _roomName = 'playtogether:default';

  final Player _player;
  final String _clientId = const Uuid().v4();

  RealtimeChannel? _channel;
  int _lastAppliedTimestamp = 0;
  bool _hasReceivedInitialState = false;
  bool _isApplyingRemoteAction = false;

  SyncService(this._player);

  /// Connect to the sync channel and start listening
  Future<void> connect() async {
    final supabase = Supabase.instance.client;

    _channel = supabase.channel(
      _roomName,
      opts: const RealtimeChannelConfig(self: false),
    );

    _channel!
        .onBroadcast(event: SyncEventType.play, callback: _handlePlay)
        .onBroadcast(event: SyncEventType.pause, callback: _handlePause)
        .onBroadcast(event: SyncEventType.seek, callback: _handleSeek)
        .onBroadcast(event: SyncEventType.stateRequest, callback: _handleStateRequest)
        .onBroadcast(event: SyncEventType.stateResponse, callback: _handleStateResponse)
        .subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _requestInitialState();
      }
    });
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
    _applyRemoteAction(() => _player.play());
  }

  void _handlePause(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    _applyRemoteAction(() => _player.pause());
  }

  void _handleSeek(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    final positionMs = payload['positionMs'] as int;
    _applyRemoteAction(() => _player.seek(Duration(milliseconds: positionMs)));
  }

  void _handleStateRequest(Map<String, dynamic> payload) {
    // Only respond if we have a video loaded
    if (_player.state.duration == Duration.zero) return;

    _channel?.sendBroadcastMessage(
      event: SyncEventType.stateResponse,
      payload: StateResponseEvent(
        senderId: _clientId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        playing: _player.state.playing,
        positionMs: _player.state.position.inMilliseconds,
      ).toPayload(),
    );
  }

  void _handleStateResponse(Map<String, dynamic> payload) {
    // Only apply first response
    if (_hasReceivedInitialState) return;
    _hasReceivedInitialState = true;

    final positionMs = payload['positionMs'] as int;
    final playing = payload['playing'] as bool;

    _applyRemoteAction(() async {
      await _player.seek(Duration(milliseconds: positionMs));
      if (playing) {
        await _player.play();
      } else {
        await _player.pause();
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
    disconnect();
  }
}
