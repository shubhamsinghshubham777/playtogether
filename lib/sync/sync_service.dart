import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:playtogether/profile/profile_models.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_events.dart';

class PresentMember {
  const PresentMember({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String role;
  final DateTime joinedAt;
  final String? avatarUrl;

  bool get isHost => role == 'host';
}

class ChatMessage {
  const ChatMessage({
    required this.senderId,
    required this.displayName,
    required this.content,
    required this.sentAt,
  });

  final String senderId;
  final String displayName;
  final String content;
  final DateTime sentAt;
}

/// Room-scoped sync engine over a private Supabase Realtime channel
/// (`room:<id>`). Created on room entry, disposed on leave.
///
/// Echo/loop prevention is a trio — do not break it:
/// 1. channel `self: false` — never receive own broadcasts;
/// 2. [_isApplyingRemoteAction] suppresses re-broadcast while applying;
/// 3. last-action-wins ordering in [_shouldApply].
class SyncService {
  SyncService(this._player, {required this.room, required this.profile, required String role})
    // ignore: prefer_initializing_formals
    : _role = role;

  final Player _player;
  final Room room;
  final Profile profile;
  String _role;

  String get userId => profile.id;
  bool get isHost => _role == 'host';

  SupabaseClient get _client => Supabase.instance.client;

  RealtimeChannel? _channel;
  int _lastAppliedTimestamp = 0;
  bool _hasReceivedInitialState = false;
  bool _isApplyingRemoteAction = false;
  Timer? _stateRequestRetry;
  Timer? _driftTimer;

  final _chatController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get chatMessages => _chatController.stream;

  final _presenceController = StreamController<List<PresentMember>>.broadcast();
  Stream<List<PresentMember>> get presenceStream => _presenceController.stream;
  List<PresentMember> _presentMembers = const [];
  List<PresentMember> get presentMembers => List.unmodifiable(_presentMembers);

  final _typingController = StreamController<List<String>>.broadcast();
  /// Display names currently typing (excluding self).
  Stream<List<String>> get typingStream => _typingController.stream;
  final _typingNames = <String, String>{};
  final _typingTimers = <String, Timer>{};

  final _modeSwitchController = StreamController<ModeSwitchEvent>.broadcast();
  Stream<ModeSwitchEvent> get modeSwitchStream => _modeSwitchController.stream;

  final _fileInfoController = StreamController<FileInfoEvent>.broadcast();
  Stream<FileInfoEvent> get fileInfoStream => _fileInfoController.stream;

  final _roomEndedController = StreamController<void>.broadcast();
  Stream<void> get roomEndedStream => _roomEndedController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  /// false while resubscribing after a drop ("Reconnecting…" banner).
  Stream<bool> get connectionStream => _connectionController.stream;

  // Dual-player routing: set by the room screen; media_kit fallback otherwise.
  void Function()? onRemotePlay;
  void Function()? onRemotePause;
  void Function(Duration)? onRemoteSeek;
  /// Silent correction for position_sync drift (must not pause YouTube).
  void Function(Duration)? onRemoteDriftCorrect;
  Duration Function()? currentPosition;
  bool Function()? isPlaying;

  String _currentMode = 'local';
  String? _currentYoutubeUrl;
  String? _currentFileName;
  int? _currentFileDurationMs;

  int _reconnectAttempts = 0;
  bool _disposed = false;

  Future<void> connect() async {
    _channel = _client.channel(
      'room:${room.id}',
      opts: const RealtimeChannelConfig(self: false, private: true),
    );

    _channel!
        .onBroadcast(event: SyncEventType.play, callback: _handlePlay)
        .onBroadcast(event: SyncEventType.pause, callback: _handlePause)
        .onBroadcast(event: SyncEventType.seek, callback: _handleSeek)
        .onBroadcast(event: SyncEventType.stateRequest, callback: _handleStateRequest)
        .onBroadcast(event: SyncEventType.stateResponse, callback: _handleStateResponse)
        .onBroadcast(event: SyncEventType.modeSwitch, callback: _handleModeSwitch)
        .onBroadcast(event: SyncEventType.chat, callback: _handleChat)
        .onBroadcast(event: SyncEventType.typing, callback: _handleTyping)
        .onBroadcast(event: SyncEventType.positionSync, callback: _handlePositionSync)
        .onBroadcast(event: SyncEventType.fileInfo, callback: _handleFileInfo)
        .onBroadcast(event: SyncEventType.roomEnded, callback: (_) => _roomEndedController.add(null))
        .onPresenceSync(_handlePresenceSync)
        .subscribe((status, error) {
          if (_disposed) return;
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              _reconnectAttempts = 0;
              _connectionController.add(true);
              _trackPresence();
              _requestInitialState();
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.closed:
              _connectionController.add(false);
              _scheduleReconnect();
            case RealtimeSubscribeStatus.timedOut:
              _connectionController.add(false);
              _scheduleReconnect();
          }
        });

    _driftTimer = Timer.periodic(const Duration(seconds: 10), (_) => _broadcastPositionSync());
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    final delay = Duration(seconds: (1 << _reconnectAttempts.clamp(0, 4)));
    _reconnectAttempts++;
    Timer(delay, () async {
      if (_disposed) return;
      await _channel?.unsubscribe();
      // A fresh joiner state-request after resubscribe re-aligns playback.
      _hasReceivedInitialState = false;
      await connect();
    });
  }

  DateTime? _membershipJoinedAt;

  /// Membership joined_at feeds authority election; fetched once.
  Future<void> loadMembership() async {
    final row = await _client
        .from('room_members')
        .select('role, joined_at')
        .eq('room_id', room.id)
        .eq('user_id', userId)
        .maybeSingle();
    if (row != null) {
      _role = row['role'] as String;
      _membershipJoinedAt = DateTime.parse(row['joined_at'] as String);
    }
  }

  void _trackPresence() {
    _channel?.track({
      'user_id': userId,
      'display_name': profile.displayName,
      'avatar_url': profile.avatarUrl,
      'role': _role,
      'joined_at': (_membershipJoinedAt ?? DateTime.now()).toIso8601String(),
    });
  }

  /// Host succession: re-announce presence with the new role.
  void updateRole(String role) {
    if (_role == role) return;
    _role = role;
    _trackPresence();
  }

  void _handlePresenceSync(RealtimePresenceSyncPayload payload) {
    final states = _channel?.presenceState();
    if (states == null) return;
    // A user with two devices counts once (keyed by user_id).
    final byUser = <String, PresentMember>{};
    for (final state in states) {
      for (final presence in state.presences) {
        final p = presence.payload;
        final uid = p['user_id'] as String?;
        if (uid == null) continue;
        byUser[uid] = PresentMember(
          userId: uid,
          displayName: p['display_name'] as String? ?? 'Watcher',
          avatarUrl: p['avatar_url'] as String?,
          role: p['role'] as String? ?? 'member',
          joinedAt: DateTime.tryParse(p['joined_at'] as String? ?? '') ?? DateTime.now(),
        );
      }
    }
    _presentMembers = byUser.values.toList()..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    _presenceController.add(_presentMembers);
  }

  // ---------------------------------------------------------------------------
  // Chat: rows in `messages` are the durable history; the broadcast is only
  // the low-latency fan-out. Late joiners read the table.
  // ---------------------------------------------------------------------------

  Future<List<ChatMessage>> loadChatHistory() async {
    final rows = await _client
        .from('messages')
        .select('sender_id, content, created_at, profiles(display_name)')
        .eq('room_id', room.id)
        .order('created_at', ascending: true)
        .limit(300);
    return rows.map<ChatMessage>((r) {
      return ChatMessage(
        senderId: r['sender_id'] as String,
        displayName:
            (r['profiles'] as Map<String, dynamic>?)?['display_name'] as String? ?? 'Watcher',
        content: r['content'] as String,
        sentAt: DateTime.parse(r['created_at'] as String),
      );
    }).toList();
  }

  Future<ChatMessage> sendChat(String content) async {
    final message = ChatMessage(
      senderId: userId,
      displayName: profile.displayName,
      content: content,
      sentAt: DateTime.now(),
    );
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.chat,
      payload: ChatEvent(
        senderId: userId,
        timestamp: message.sentAt.millisecondsSinceEpoch,
        displayName: profile.displayName,
        message: content,
      ).toPayload(),
    );
    unawaited(
      _client.from('messages').insert({
        'room_id': room.id,
        'sender_id': userId,
        'content': content,
      }),
    );
    return message;
  }

  void _handleChat(Map<String, dynamic> payload) {
    final event = ChatEvent.fromPayload(payload);
    _chatController.add(
      ChatMessage(
        senderId: event.senderId,
        displayName: event.displayName,
        content: event.message,
        sentAt: DateTime.fromMillisecondsSinceEpoch(event.timestamp),
      ),
    );
  }

  Future<void> broadcastTyping(bool isTyping) async {
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.typing,
      payload: TypingEvent(
        senderId: userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        displayName: profile.displayName,
        isTyping: isTyping,
      ).toPayload(),
    );
  }

  void _handleTyping(Map<String, dynamic> payload) {
    final event = TypingEvent.fromPayload(payload);
    _typingTimers.remove(event.senderId)?.cancel();
    if (event.isTyping) {
      _typingNames[event.senderId] = event.displayName;
      _typingTimers[event.senderId] = Timer(const Duration(seconds: 4), () {
        _typingNames.remove(event.senderId);
        _typingTimers.remove(event.senderId);
        _emitTyping();
      });
    } else {
      _typingNames.remove(event.senderId);
    }
    _emitTyping();
  }

  void _emitTyping() => _typingController.add(_typingNames.values.toList());

  // ---------------------------------------------------------------------------
  // Playback control (any member; last-action-wins resolves races)
  // ---------------------------------------------------------------------------

  Future<void> broadcastPlay() async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.play,
      payload: PlayEvent(
        senderId: userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ).toPayload(),
    );
  }

  Future<void> broadcastPause() async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.pause,
      payload: PauseEvent(
        senderId: userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ).toPayload(),
    );
  }

  Future<void> broadcastSeek(Duration position) async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.seek,
      payload: SeekEvent(
        senderId: userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        positionMs: position.inMilliseconds,
      ).toPayload(),
    );
  }

  Future<void> broadcastModeSwitch(String mode, String? youtubeUrl) async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.modeSwitch,
      payload: ModeSwitchEvent(
        senderId: userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        mode: mode,
        youtubeUrl: youtubeUrl,
      ).toPayload(),
    );
  }

  Future<void> broadcastFileInfo(String fileName, Duration duration) async {
    _currentFileName = fileName;
    _currentFileDurationMs = duration.inMilliseconds;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.fileInfo,
      payload: FileInfoEvent(
        senderId: userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        fileName: fileName,
        durationMs: duration.inMilliseconds,
      ).toPayload(),
    );
  }

  /// Sent by the host's client on "end room" and at expiry so members
  /// evict instantly instead of waiting for their own countdown.
  Future<void> broadcastRoomEnded() async {
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.roomEnded,
      payload: {'senderId': userId, 'timestamp': DateTime.now().millisecondsSinceEpoch},
    );
  }

  void updatePlaybackState(String mode, String? youtubeUrl) {
    _currentMode = mode;
    _currentYoutubeUrl = youtubeUrl;
    if (mode != 'local') {
      _currentFileName = null;
      _currentFileDurationMs = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Late-joiner state sync: only the authority answers (host if present, else
  // earliest-joined present member) — avoids N-1 redundant responses.
  // ---------------------------------------------------------------------------

  void _requestInitialState() {
    if (_hasReceivedInitialState) return;
    _channel?.sendBroadcastMessage(
      event: SyncEventType.stateRequest,
      payload: StateRequestEvent(
        senderId: userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ).toPayload(),
    );
    _stateRequestRetry?.cancel();
    _stateRequestRetry = Timer(const Duration(seconds: 2), () {
      if (_hasReceivedInitialState || _disposed) return;
      _channel?.sendBroadcastMessage(
        event: SyncEventType.stateRequest,
        payload: StateRequestEvent(
          senderId: userId,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ).toPayload(),
      );
      // After the retry window, assume an idle room.
      _stateRequestRetry = Timer(const Duration(seconds: 2), () {
        _hasReceivedInitialState = true;
      });
    });
  }

  bool get _isAuthority {
    final present = _presentMembers.where((m) => m.userId != userId).toList();
    final self = PresentMember(
      userId: userId,
      displayName: profile.displayName,
      role: _role,
      joinedAt: _membershipJoinedAt ?? DateTime.now(),
    );
    final candidates = [...present, self];
    final host = candidates.where((m) => m.isHost).firstOrNull;
    final authority = host ?? candidates.reduce((a, b) {
      final cmp = a.joinedAt.compareTo(b.joinedAt);
      if (cmp != 0) return cmp < 0 ? a : b;
      return a.userId.compareTo(b.userId) < 0 ? a : b;
    });
    return authority.userId == userId;
  }

  void _handleStateRequest(Map<String, dynamic> payload) {
    if (!_isAuthority) return;
    final hasMedia = _player.state.duration != Duration.zero || _currentYoutubeUrl != null;
    if (!hasMedia) return;

    _channel?.sendBroadcastMessage(
      event: SyncEventType.stateResponse,
      payload: StateResponseEvent(
        senderId: userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        playing: isPlaying?.call() ?? _player.state.playing,
        positionMs: (currentPosition?.call() ?? _player.state.position).inMilliseconds,
        mode: _currentMode,
        youtubeUrl: _currentYoutubeUrl,
        fileName: _currentFileName,
        fileDurationMs: _currentFileDurationMs,
      ).toPayload(),
    );
  }

  void _handleStateResponse(Map<String, dynamic> payload) {
    if (_hasReceivedInitialState) return;
    _hasReceivedInitialState = true;
    _stateRequestRetry?.cancel();

    final event = StateResponseEvent.fromPayload(payload);

    if (event.mode != 'local' || event.youtubeUrl != null) {
      _modeSwitchController.add(
        ModeSwitchEvent(
          senderId: event.senderId,
          timestamp: event.timestamp,
          mode: event.mode,
          youtubeUrl: event.youtubeUrl,
        ),
      );
    } else if (event.fileName != null) {
      _fileInfoController.add(
        FileInfoEvent(
          senderId: event.senderId,
          timestamp: event.timestamp,
          fileName: event.fileName!,
          durationMs: event.fileDurationMs ?? 0,
        ),
      );
    }

    _applyRemoteAction(() async {
      // Wait for the mode switch to land before seeking.
      await Future.delayed(const Duration(milliseconds: 500));
      if (onRemoteSeek != null) {
        onRemoteSeek!(Duration(milliseconds: event.positionMs));
      } else {
        await _player.seek(Duration(milliseconds: event.positionMs));
      }
      if (event.playing) {
        onRemotePlay != null ? onRemotePlay!() : await _player.play();
      } else {
        onRemotePause != null ? onRemotePause!() : await _player.pause();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Drift correction (host heartbeat every 10 s while playing)
  // ---------------------------------------------------------------------------

  static const _driftThreshold = Duration(milliseconds: 1500);

  void _broadcastPositionSync() {
    if (!isHost || _isApplyingRemoteAction) return;
    final playing = isPlaying?.call() ?? _player.state.playing;
    if (!playing) return;
    _channel?.sendBroadcastMessage(
      event: SyncEventType.positionSync,
      payload: PositionSyncEvent(
        senderId: userId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        positionMs: (currentPosition?.call() ?? _player.state.position).inMilliseconds,
        playing: playing,
      ).toPayload(),
    );
  }

  void _handlePositionSync(Map<String, dynamic> payload) {
    final event = PositionSyncEvent.fromPayload(payload);
    final localPlaying = isPlaying?.call() ?? _player.state.playing;
    if (!event.playing || !localPlaying) return;
    final local = currentPosition?.call() ?? _player.state.position;
    final remote = Duration(milliseconds: event.positionMs);
    if ((local - remote).abs() <= _driftThreshold) return;
    _applyRemoteAction(() {
      if (onRemoteDriftCorrect != null) {
        onRemoteDriftCorrect!(remote);
      } else if (onRemoteSeek != null) {
        onRemoteSeek!(remote);
      } else {
        _player.seek(remote);
      }
    });
  }

  void _handleFileInfo(Map<String, dynamic> payload) {
    _fileInfoController.add(FileInfoEvent.fromPayload(payload));
  }

  // ---------------------------------------------------------------------------
  // Remote action application
  // ---------------------------------------------------------------------------

  void _handlePlay(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    _applyRemoteAction(() {
      onRemotePlay != null ? onRemotePlay!() : _player.play();
    });
  }

  void _handlePause(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    _applyRemoteAction(() {
      onRemotePause != null ? onRemotePause!() : _player.pause();
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
    _modeSwitchController.add(ModeSwitchEvent.fromPayload(payload));
  }

  bool _shouldApply(Map<String, dynamic> payload) {
    final senderId = payload['senderId'] as String;
    final timestamp = payload['timestamp'] as int;
    // self:false should exclude own events; defensive double-check.
    if (senderId == userId) return false;
    if (timestamp <= _lastAppliedTimestamp) return false;
    _lastAppliedTimestamp = timestamp;
    return true;
  }

  void _applyRemoteAction(dynamic Function() action) {
    _isApplyingRemoteAction = true;
    action();
    // Settle delay before re-arming broadcasts.
    Future.delayed(const Duration(milliseconds: 100), () {
      _isApplyingRemoteAction = false;
    });
  }

  Future<void> disconnect() async {
    _driftTimer?.cancel();
    _stateRequestRetry?.cancel();
    await _channel?.unsubscribe();
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _chatController.close();
    _presenceController.close();
    _typingController.close();
    _modeSwitchController.close();
    _fileInfoController.close();
    _roomEndedController.close();
    _connectionController.close();
    disconnect();
  }
}
