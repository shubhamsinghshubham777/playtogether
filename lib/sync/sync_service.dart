import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playtogether/profile/profile_models.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/rooms/room_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_events.dart';

/// How far a member has got towards having the room's canonical media loaded.
/// Declaration order is the rank — "more ready" compares by [index], which is
/// what resolves a multi-device user to a single status.
enum ReadyStatus {
  none,
  selecting,
  loading,
  ready;

  static ReadyStatus fromWire(String? value) => switch (value) {
    'selecting' => .selecting,
    'loading' => .loading,
    'ready' => .ready,
    _ => .none,
  };

  String get wire => name;
}

class PresentMember {
  const PresentMember({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.avatarUrl,
    this.readyStatus = .none,
    this.loadedFileName,
  });

  final String userId;
  final String displayName;
  final String role;
  final DateTime joinedAt;
  final String? avatarUrl;

  /// A client that predates the readiness gate sends no status, which reads as
  /// [ReadyStatus.none] and holds the gate shut — the accepted trade-off.
  final ReadyStatus readyStatus;

  /// Basename this member actually has open, for the "they have `weird.mp4`" copy.
  final String? loadedFileName;

  bool get isHost => role == 'host';
  bool get isReady => readyStatus == .ready;
}

/// Tri-state on purpose: before the first presence sync we simply don't know
/// who is in the room, and rendering that as `closed` flashes the waiting
/// overlay on every entry.
enum GateState { indeterminate, open, closed }

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

enum RemoteActionKind { play, pause, seek }

/// A user-initiated remote playback action, surfaced for attribution UI. Only
/// emitted for genuine play/pause/seek broadcasts — never for mechanical
/// `state_response` application or `position_sync` drift correction, so
/// late-join and drift never read as someone touching the controls.
class RemoteAction {
  const RemoteAction({required this.senderId, required this.kind, this.position});

  final String senderId;
  final RemoteActionKind kind;
  final Duration? position;
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
    : _role = role {
    _canonicalMedia = RoomMedia.fromRoom(room);
  }

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

  bool _hasPresenceSynced = false;
  /// False until the first presence sync lands. Readiness is unknowable until
  /// then, so the gate must read as indeterminate rather than closed — else
  /// every room entry flashes the waiting overlay.
  bool get hasPresenceSynced => _hasPresenceSynced;

  final _typingController = StreamController<List<String>>.broadcast();
  /// Display names currently typing (excluding self).
  Stream<List<String>> get typingStream => _typingController.stream;
  final _typingNames = <String, String>{};
  final _typingTimers = <String, Timer>{};

  final _modeSwitchController = StreamController<ModeSwitchEvent>.broadcast();
  Stream<ModeSwitchEvent> get modeSwitchStream => _modeSwitchController.stream;

  final _fileInfoController = StreamController<FileInfoEvent>.broadcast();
  Stream<FileInfoEvent> get fileInfoStream => _fileInfoController.stream;

  RoomMedia _canonicalMedia = RoomMedia.none;
  final _canonicalMediaController = StreamController<RoomMedia>.broadcast();
  /// Emits only when genuinely newer media is adopted, so listeners never see a
  /// stale refetch undo a broadcast they already applied.
  Stream<RoomMedia> get canonicalMediaStream => _canonicalMediaController.stream;
  RoomMedia get canonicalMedia => _canonicalMedia;

  final _gateController = StreamController<GateState>.broadcast();
  Stream<GateState> get gateStream => _gateController.stream;
  GateState _lastGateState = GateState.indeterminate;

  /// True on **every** client once a gate-derived pause lands, not just the one
  /// that emitted it — otherwise host succession mid-wait would lose the flag
  /// and auto-resume would never fire. Any human play/pause clears it, which is
  /// what stops auto-resume from overriding a deliberate pause.
  bool _pausedByGate = false;
  Duration? _gateHeldPosition;

  /// Whether the *room* is playing, which is not the same as whether our own
  /// player is. When the host opens a new file their player stops while
  /// everyone else keeps playing, and that is precisely when the gate needs to
  /// pause the room — so the decision can't be made from `isPlaying`.
  bool _roomPlaying = false;

  /// `ready` only means "something is open" — the name comparison is the
  /// gate's job, which is what lets the UI tell "still loading" apart from
  /// "loaded the wrong thing".
  bool memberSatisfiesGate(PresentMember member) {
    if (!member.isReady) return false;
    if (_canonicalMedia.kind == .local && member.loadedFileName != _canonicalMedia.name) {
      return false;
    }
    return true;
  }

  /// Nobody may start or scrub until every present member has the room's
  /// canonical media loaded.
  GateState get gateState {
    if (!_hasPresenceSynced) return .indeterminate;
    if (!_canonicalMedia.isSet) return .closed;
    if (_presentMembers.isEmpty) return .indeterminate;
    return _presentMembers.every(memberSatisfiesGate) ? .open : .closed;
  }

  /// Everyone the room is still waiting on, for overlay/banner copy.
  List<PresentMember> get gateBlockers => _canonicalMedia.isSet
      ? _presentMembers.where((m) => !memberSatisfiesGate(m)).toList()
      : const [];

  PresentMember? get gateBlocker => gateBlockers.firstOrNull;

  final _roomEndedController = StreamController<void>.broadcast();
  Stream<void> get roomEndedStream => _roomEndedController.stream;

  final _gateResumedController = StreamController<void>.broadcast();
  /// Fires on every client when the gate reopens and playback auto-resumes,
  /// so the resume reads as deliberate rather than as a glitch (D11).
  Stream<void> get gateResumedStream => _gateResumedController.stream;

  final _kickedController = StreamController<void>.broadcast();
  /// Fires only on the client that was removed.
  Stream<void> get kickedStream => _kickedController.stream;

  final _remoteActionController = StreamController<RemoteAction>.broadcast();
  /// User-initiated remote play/pause/seek, for attribution toasts.
  Stream<RemoteAction> get remoteActions => _remoteActionController.stream;

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
  Timer? _reconnectTimer;
  bool _disposed = false;
  // Intentional teardown (eviction/leave). unsubscribe() surfaces as a `closed`
  // status in the subscribe callback, which must NOT schedule a reconnect then.
  bool _tearingDown = false;

  /// Broadcasts normally arrive flat (the sender's `send()` merges `type` and
  /// `event` into our own map), but `realtime_client` falls back to the REST
  /// endpoint whenever the channel isn't pushable yet, and that path delivers
  /// the user payload nested one level down. Accept both shapes.
  Map<String, dynamic> _unwrapPayload(Map<String, dynamic> payload) {
    final inner = payload['payload'];
    return inner is Map ? Map<String, dynamic>.from(inner) : payload;
  }

  /// A throw inside a realtime callback propagates into the socket's stream
  /// handler and can take the whole channel's message processing down with it
  /// — one malformed event would silently kill sync for the rest of the
  /// session. Every broadcast handler goes through here.
  void Function(Map<String, dynamic>) _guard(
    void Function(Map<String, dynamic>) handler,
  ) {
    return (payload) {
      try {
        handler(_unwrapPayload(payload));
      } catch (error, stack) {
        debugPrint('sync: dropped a malformed broadcast — $error\n$stack');
      }
    };
  }

  Future<void> connect() async {
    final channel = _client.channel(
      'room:${room.id}',
      opts: const RealtimeChannelConfig(self: false, private: true),
    );
    _channel = channel;

    channel
        .onBroadcast(event: SyncEventType.play, callback: _guard(_handlePlay))
        .onBroadcast(event: SyncEventType.pause, callback: _guard(_handlePause))
        .onBroadcast(event: SyncEventType.seek, callback: _guard(_handleSeek))
        .onBroadcast(event: SyncEventType.stateRequest, callback: _guard(_handleStateRequest))
        .onBroadcast(event: SyncEventType.stateResponse, callback: _guard(_handleStateResponse))
        .onBroadcast(event: SyncEventType.modeSwitch, callback: _guard(_handleModeSwitch))
        .onBroadcast(event: SyncEventType.chat, callback: _guard(_handleChat))
        .onBroadcast(event: SyncEventType.typing, callback: _guard(_handleTyping))
        .onBroadcast(event: SyncEventType.positionSync, callback: _guard(_handlePositionSync))
        .onBroadcast(event: SyncEventType.fileInfo, callback: _guard(_handleFileInfo))
        .onBroadcast(event: SyncEventType.mediaSet, callback: _guard(_handleMediaSet))
        .onBroadcast(event: SyncEventType.memberKicked, callback: _guard(_handleMemberKicked))
        .onBroadcast(event: SyncEventType.transportLock, callback: _guard(_handleTransportLock))
        .onBroadcast(event: SyncEventType.roomEnded, callback: _guard(_handleRoomEnded))
        .onPresenceSync(_handlePresenceSync)
        .subscribe((status, error) {
          // Statuses from a superseded channel (reconnect replaced it) are stale.
          if (_disposed || _tearingDown || !identical(channel, _channel)) return;
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              _reconnectAttempts = 0;
              _connectionController.add(true);
              _trackPresence();
              _reannounceFileInfo();
              unawaited(refreshCanonicalMedia());
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

    _driftTimer?.cancel();
    _driftTimer = Timer.periodic(const Duration(seconds: 10), (_) => _broadcastPositionSync());
  }

  void _scheduleReconnect() {
    if (_disposed || _tearingDown) return;
    if (_reconnectTimer?.isActive ?? false) return;
    final delay = Duration(seconds: (1 << _reconnectAttempts.clamp(0, 4)));
    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, () async {
      if (_disposed || _tearingDown) return;
      // Detach before unsubscribing so the old channel's `closed` is ignored.
      final old = _channel;
      _channel = null;
      await old?.unsubscribe();
      // A fresh joiner state-request after resubscribe re-aligns playback.
      _hasReceivedInitialState = false;
      await connect();
    });
  }

  void _handleRoomEnded(Map<String, dynamic> payload) {
    if (_disposed) return;
    _roomEndedController.add(null);
  }

  bool _transportLock = false;
  final _transportLockController = StreamController<bool>.broadcast();
  Stream<bool> get transportLockStream => _transportLockController.stream;
  bool get transportLock => _transportLock;

  /// Room-level like canonical media: the row is the truth, this is fan-out.
  /// [refreshCanonicalMedia] re-reads it on entry and every resubscribe, so a
  /// missed broadcast self-heals.
  Future<void> broadcastTransportLock(bool locked) async {
    _setTransportLock(locked);
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.transportLock,
      payload: {
        'senderId': userId,
        'timestamp': _nextTimestamp(),
        'locked': locked,
      },
    );
  }

  void _handleTransportLock(Map<String, dynamic> payload) {
    if (_disposed) return;
    _setTransportLock(payload['locked'] as bool? ?? false);
  }

  void _setTransportLock(bool locked) {
    if (_transportLock == locked) return;
    _transportLock = locked;
    _transportLockController.add(locked);
  }

  /// Sent by the host after `kick_member` succeeds. Deleting the membership row
  /// does not eject anyone — Realtime authorizes a private channel at
  /// *subscribe* time, so an already-connected client keeps receiving until it
  /// resubscribes. This broadcast is what actually removes them.
  Future<void> broadcastMemberKicked(String targetUserId) async {
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.memberKicked,
      payload: {
        'senderId': userId,
        'timestamp': _nextTimestamp(),
        'targetUserId': targetUserId,
      },
    );
  }

  void _handleMemberKicked(Map<String, dynamic> payload) {
    if (_disposed) return;
    if (payload['targetUserId'] != userId) return;
    _kickedController.add(null);
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

  ReadyStatus _readyStatus = .none;
  String? _loadedFileName;

  ReadyStatus get readyStatus => _readyStatus;
  String? get loadedFileName => _loadedFileName;

  void _trackPresence() {
    _channel?.track({
      'user_id': userId,
      'display_name': profile.displayName,
      'avatar_url': profile.avatarUrl,
      'role': _role,
      'joined_at': (_membershipJoinedAt ?? DateTime.now()).toIso8601String(),
      'ready_status': _readyStatus.wire,
      'loaded_file_name': _loadedFileName,
    });
  }

  /// Host succession: re-announce presence with the new role.
  void updateRole(String role) {
    if (_role == role) return;
    _role = role;
    _trackPresence();
  }

  /// Own readiness -> presence. Presence carries the gate because it replays to
  /// joiners automatically and dies with the connection, so a member who drops
  /// stops holding the gate shut without anyone having to notice.
  ///
  /// [_readyStatus] survives reconnects, so the `_trackPresence()` in the
  /// subscribe callback re-announces it for free — that is the whole of the
  /// "re-announce readiness on resubscribe" requirement.
  ///
  /// The pair is announced as a whole: omitting [loadedFileName] clears it, so
  /// pass it on every call where a file is open.
  void retrackReadiness(ReadyStatus status, {String? loadedFileName}) {
    if (_readyStatus == status && _loadedFileName == loadedFileName) return;
    _readyStatus = status;
    _loadedFileName = loadedFileName;
    _trackPresence();
    _checkSelfGateSatisfaction();
  }

  bool _selfSatisfiesGate = false;

  /// Watches our own crossing into "has the room's media open". Readiness and
  /// the canonical media arrive from different directions (presence vs. the
  /// `rooms` row) and in either order, so both paths funnel through here.
  void _checkSelfGateSatisfaction() {
    final satisfies = _canonicalMedia.isSet && memberSatisfiesGate(_selfPresence);
    if (satisfies == _selfSatisfiesGate) return;
    _selfSatisfiesGate = satisfies;
    if (satisfies) _resyncRoomPosition();
  }

  /// The room's position, asked for again now that there is something to apply
  /// it to. A late joiner's entry `state_request` is answered while the file
  /// picker is still open, so the seek lands on an empty player and is lost —
  /// and opening a file afterwards starts at 0.
  ///
  /// A *playing* room heals itself: the joiner's arrival shuts the gate, which
  /// pauses everyone at a held position, and the reopen broadcasts a seek back
  /// to it. A room that was already paused has no such moment — nothing moves,
  /// so nothing is broadcast — which is how the joiner ends up parked at 0
  /// while everyone else sits where the host paused.
  void _resyncRoomPosition() {
    if (_disposed || _channel == null) return;
    if (_roomPlaying || _pausedByGate) return;
    // Alone in the room: nobody to answer, and our own position *is* the room's.
    if (_hasPresenceSynced && _presentMembers.every((m) => m.userId == userId)) {
      return;
    }
    _hasReceivedInitialState = false;
    _requestInitialState();
  }

  void _handlePresenceSync(RealtimePresenceSyncPayload payload) {
    if (_disposed) return;
    final states = _channel?.presenceState();
    if (states == null) return;
    // A user with two devices counts once (keyed by user_id).
    final byUser = <String, PresentMember>{};
    for (final state in states) {
      for (final presence in state.presences) {
        final p = presence.payload;
        final uid = p['user_id'] as String?;
        if (uid == null) continue;
        final member = PresentMember(
          userId: uid,
          displayName: p['display_name'] as String? ?? 'Watcher',
          avatarUrl: p['avatar_url'] as String?,
          role: p['role'] as String? ?? 'member',
          joinedAt: DateTime.tryParse(p['joined_at'] as String? ?? '') ?? DateTime.now(),
          readyStatus: ReadyStatus.fromWire(p['ready_status'] as String?),
          loadedFileName: p['loaded_file_name'] as String?,
        );
        // Of a user's devices the most-ready one wins, so a second idle device
        // can't drag them back below the gate. Everything else in the payload
        // is per-user, not per-device, so picking a winner loses nothing.
        final existing = byUser[uid];
        if (existing == null || member.readyStatus.index > existing.readyStatus.index) {
          byUser[uid] = member;
        }
      }
    }
    _hasPresenceSynced = true;
    _presentMembers = byUser.values.toList()..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    _presenceController.add(_presentMembers);
    _evaluateGate();
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
    // Broadcast is best-effort fan-out; the DB row is the durable copy. Either
    // may fail independently (mid-reconnect, room just expired) without
    // crashing the send.
    try {
      await _channel?.sendBroadcastMessage(
        event: SyncEventType.chat,
        payload: ChatEvent(
          senderId: userId,
          timestamp: message.sentAt.millisecondsSinceEpoch,
          displayName: profile.displayName,
          message: content,
        ).toPayload(),
      );
    } catch (_) {}
    unawaited(() async {
      try {
        await _client.from('messages').insert({
          'room_id': room.id,
          'sender_id': userId,
          'content': content,
        });
      } catch (_) {}
    }());
    return message;
  }

  void _handleChat(Map<String, dynamic> payload) {
    if (_disposed) return;
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
        timestamp: _nextTimestamp(),
        displayName: profile.displayName,
        isTyping: isTyping,
      ).toPayload(),
    );
  }

  void _handleTyping(Map<String, dynamic> payload) {
    if (_disposed) return;
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

  void _emitTyping() {
    if (_disposed) return;
    _typingController.add(_typingNames.values.toList());
  }

  // ---------------------------------------------------------------------------
  // Playback control (any member; last-action-wins resolves races)
  // ---------------------------------------------------------------------------

  Future<void> broadcastPlay({String? reason, String? subjectUserId}) async {
    if (_isApplyingRemoteAction) return;
    _roomPlaying = true;
    // A human acting supersedes the gate's pause: never auto-resume on top of
    // a deliberate decision made while the room was waiting.
    if (reason == null) _pausedByGate = false;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.play,
      payload: PlayEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
        reason: reason,
        subjectUserId: subjectUserId,
      ).toPayload(),
    );
  }

  Future<void> broadcastPause({String? reason, String? subjectUserId}) async {
    if (_isApplyingRemoteAction) return;
    _roomPlaying = false;
    if (reason == null) _pausedByGate = false;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.pause,
      payload: PauseEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
        reason: reason,
        subjectUserId: subjectUserId,
      ).toPayload(),
    );
  }

  Future<void> broadcastSeek(Duration position, {String? reason}) async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.seek,
      payload: SeekEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
        positionMs: position.inMilliseconds,
        reason: reason,
      ).toPayload(),
    );
  }

  Future<void> broadcastModeSwitch(String mode, String? youtubeUrl) async {
    if (_isApplyingRemoteAction) return;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.modeSwitch,
      payload: ModeSwitchEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
        mode: mode,
        youtubeUrl: youtubeUrl,
      ).toPayload(),
    );
  }

  // ---------------------------------------------------------------------------
  // Canonical media: the `rooms` row is the source of truth, `media_set` is
  // fan-out. Broadcasts never replay, so refetch on entry and on every
  // resubscribe — same doctrine as chat history.
  // ---------------------------------------------------------------------------

  void _adoptCanonicalMedia(RoomMedia media) {
    if (!media.isNewerThan(_canonicalMedia)) return;
    _canonicalMedia = media;
    _canonicalMediaController.add(media);
    _checkSelfGateSatisfaction();
    _evaluateGate();
  }

  // ---------------------------------------------------------------------------
  // The gate. Strict lockstep: a member swapping files mid-play or a late
  // joiner arriving system-pauses everyone, and playback auto-resumes at the
  // held position once everyone is ready again.
  // ---------------------------------------------------------------------------

  void _evaluateGate() {
    if (_disposed) return;
    final state = gateState;
    if (state == _lastGateState) return;
    final previous = _lastGateState;
    _lastGateState = state;
    _gateController.add(state);

    // Derived actions come from the authority alone. If every client reacted to
    // the same observation the room would get one pause per member.
    if (!_isAuthority) return;

    if (state == GateState.closed && previous == GateState.open) {
      if (!_roomPlaying) return;
      final blocker = gateBlocker;
      // Our own position is only meaningful if we still have the room's media
      // loaded. If we're the one holding the gate up we've just opened
      // something else and sit at 0 — resuming everyone there would throw the
      // room back to the start. A null held position simply skips the
      // realignment seek, and everyone resumes where they paused, which is
      // already the same spot.
      _gateHeldPosition = blocker?.userId == userId ? null : currentPosition?.call();
      _pausedByGate = true;
      // Broadcast BEFORE applying: broadcastPause() bails out while
      // _isApplyingRemoteAction is set, so the reverse order sends nothing.
      unawaited(
        broadcastPause(
          reason: SyncActionReason.gate,
          subjectUserId: gateBlocker?.userId,
        ),
      );
      _applyRemoteAction(() {
        onRemotePause != null ? onRemotePause!() : _player.pause();
      });
    } else if (state == GateState.open &&
        previous == GateState.closed &&
        _pausedByGate) {
      _pausedByGate = false;
      final resumeAt = _gateHeldPosition;
      _gateHeldPosition = null;
      if (resumeAt != null) {
        unawaited(broadcastSeek(resumeAt, reason: SyncActionReason.gate));
      }
      unawaited(broadcastPlay(reason: SyncActionReason.gate));
      _gateResumedController.add(null);
      _applyRemoteAction(() {
        if (resumeAt != null) onRemoteSeek?.call(resumeAt);
        onRemotePlay != null ? onRemotePlay!() : _player.play();
      });
    }
  }

  Future<void> refreshCanonicalMedia() async {
    try {
      final fresh = await RoomService.instance.fetchRoom(room.id);
      if (_disposed || fresh == null) return;
      _setTransportLock(fresh.transportLock);
      _adoptCanonicalMedia(RoomMedia.fromRoom(fresh));
    } catch (_) {}
  }

  /// Host only (the RPC enforces it). Adopts locally first because the channel
  /// is `self: false` — the sender never receives its own broadcast.
  Future<void> broadcastMediaSet(RoomMedia media) async {
    _adoptCanonicalMedia(media);
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.mediaSet,
      payload: MediaSetEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
        kind: media.kind.wire,
        name: media.name,
        durationMs: media.duration?.inMilliseconds,
        url: media.url,
        updatedAtMs: media.updatedAt?.millisecondsSinceEpoch,
      ).toPayload(),
    );
  }

  void _handleMediaSet(Map<String, dynamic> payload) {
    if (_disposed) return;
    final event = MediaSetEvent.fromPayload(payload);
    _adoptCanonicalMedia(
      RoomMedia(
        kind: RoomMediaKind.fromWire(event.kind),
        name: event.name,
        duration: event.durationMs != null
            ? Duration(milliseconds: event.durationMs!)
            : null,
        url: event.url,
        updatedAt: event.updatedAtMs != null
            ? DateTime.fromMillisecondsSinceEpoch(event.updatedAtMs!)
            : null,
      ),
    );
  }

  /// `file_info` used to fire exactly once, on pick, so anyone who joined or
  /// reconnected later never learned what this client had open. Re-announcing
  /// on every resubscribe is what closes that hole.
  void _reannounceFileInfo() {
    final name = _currentFileName;
    final durationMs = _currentFileDurationMs;
    if (name == null || durationMs == null) return;
    unawaited(broadcastFileInfo(name, Duration(milliseconds: durationMs)));
  }

  Future<void> broadcastFileInfo(String fileName, Duration duration) async {
    _currentFileName = fileName;
    _currentFileDurationMs = duration.inMilliseconds;
    await _channel?.sendBroadcastMessage(
      event: SyncEventType.fileInfo,
      payload: FileInfoEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
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
      payload: {'senderId': userId, 'timestamp': _nextTimestamp()},
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
        timestamp: _nextTimestamp(),
      ).toPayload(),
    );
    _stateRequestRetry?.cancel();
    _stateRequestRetry = Timer(const Duration(seconds: 2), () {
      if (_hasReceivedInitialState || _disposed) return;
      _channel?.sendBroadcastMessage(
        event: SyncEventType.stateRequest,
        payload: StateRequestEvent(
          senderId: userId,
          timestamp: _nextTimestamp(),
        ).toPayload(),
      );
      // After the retry window, assume an idle room.
      _stateRequestRetry = Timer(const Duration(seconds: 2), () {
        _hasReceivedInitialState = true;
      });
    });
  }

  /// Presence as *we* would broadcast it — [_presentMembers] carries everyone
  /// else's, but a client's own entry can lag its local state by a round trip.
  PresentMember get _selfPresence => PresentMember(
    userId: userId,
    displayName: profile.displayName,
    role: _role,
    joinedAt: _membershipJoinedAt ?? DateTime.now(),
    readyStatus: _readyStatus,
    loadedFileName: _loadedFileName,
  );

  List<PresentMember> get _authorityCandidates => [
    ..._presentMembers.where((m) => m.userId != userId),
    _selfPresence,
  ];

  /// Host if present, else the earliest joiner; user id breaks ties so every
  /// client elects the same person.
  String? _authorityAmong(Iterable<PresentMember> candidates) {
    if (candidates.isEmpty) return null;
    final host = candidates.where((m) => m.isHost).firstOrNull;
    if (host != null) return host.userId;
    return candidates.reduce((a, b) {
      final cmp = a.joinedAt.compareTo(b.joinedAt);
      if (cmp != 0) return cmp < 0 ? a : b;
      return a.userId.compareTo(b.userId) < 0 ? a : b;
    }).userId;
  }

  bool get _isAuthority => _authorityAmong(_authorityCandidates) == userId;

  void _handleStateRequest(Map<String, dynamic> payload) {
    // The authority answers — except when the authority is the one asking (a
    // host reopening their own room), where the next in line answers instead.
    // Excluding the requester keeps it to exactly one responder either way.
    final requesterId = payload['senderId'] as String?;
    final responder = _authorityAmong(
      _authorityCandidates.where((m) => m.userId != requesterId),
    );
    if (responder != userId) return;
    final hasMedia = _player.state.duration != Duration.zero || _currentYoutubeUrl != null;
    if (!hasMedia) return;

    _channel?.sendBroadcastMessage(
      event: SyncEventType.stateResponse,
      payload: StateResponseEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
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
    if (_disposed) return;
    if (_hasReceivedInitialState) return;
    _hasReceivedInitialState = true;
    _stateRequestRetry?.cancel();

    final event = StateResponseEvent.fromPayload(payload);
    // Late joiner: this is the first honest read of whether the room is playing.
    _roomPlaying = event.playing;

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
        timestamp: _nextTimestamp(),
        positionMs: (currentPosition?.call() ?? _player.state.position).inMilliseconds,
        playing: playing,
      ).toPayload(),
    );
  }

  void _handlePositionSync(Map<String, dynamic> payload) {
    final event = PositionSyncEvent.fromPayload(payload);
    _roomPlaying = event.playing; // authority heartbeat keeps this honest
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
    if (_disposed) return;
    _fileInfoController.add(FileInfoEvent.fromPayload(payload));
  }

  // ---------------------------------------------------------------------------
  // Remote action application
  // ---------------------------------------------------------------------------

  void _handlePlay(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    final reason = payload['reason'] as String?;
    _roomPlaying = true;
    // Gate actions are mechanical — attribution toasts are for humans only.
    if (reason == null) {
      _pausedByGate = false;
      _emitRemoteAction(payload, RemoteActionKind.play);
    } else if (reason == SyncActionReason.gate) {
      _pausedByGate = false;
      _gateResumedController.add(null);
    }
    _applyRemoteAction(() {
      onRemotePlay != null ? onRemotePlay!() : _player.play();
    });
  }

  void _handlePause(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    final reason = payload['reason'] as String?;
    _roomPlaying = false;
    if (reason == SyncActionReason.gate) {
      // Read the position before the pause lands, and remember it on every
      // client: whoever is authority when the gate reopens does the resuming.
      // Same caveat as the emitting side — if we're the member being waited on,
      // our position is about some other file, so don't record it.
      final subject = payload['subjectUserId'] as String?;
      _gateHeldPosition = subject == userId ? null : currentPosition?.call();
      _pausedByGate = true;
    } else {
      _pausedByGate = false;
      _emitRemoteAction(payload, RemoteActionKind.pause);
    }
    _applyRemoteAction(() {
      onRemotePause != null ? onRemotePause!() : _player.pause();
    });
  }

  void _handleSeek(Map<String, dynamic> payload) {
    if (!_shouldApply(payload)) return;
    final positionMs = payload['positionMs'] as int;
    // A mechanical seek (the realignment riding along with a play/pause, or a
    // gate resume) is not something anyone did — attributing it would both be
    // wrong and overwrite the play/pause toast that IS correct.
    if (payload['reason'] == null) {
      _emitRemoteAction(payload, RemoteActionKind.seek, Duration(milliseconds: positionMs));
    }
    _applyRemoteAction(() {
      if (onRemoteSeek != null) {
        onRemoteSeek!(Duration(milliseconds: positionMs));
      } else {
        _player.seek(Duration(milliseconds: positionMs));
      }
    });
  }

  void _emitRemoteAction(Map<String, dynamic> payload, RemoteActionKind kind, [Duration? position]) {
    if (_disposed) return;
    _remoteActionController.add(
      RemoteAction(senderId: payload['senderId'] as String, kind: kind, position: position),
    );
  }

  void _handleModeSwitch(Map<String, dynamic> payload) {
    if (_disposed || !_shouldApply(payload)) return;
    _modeSwitchController.add(ModeSwitchEvent.fromPayload(payload));
  }

  int _lastIssuedTimestamp = 0;

  /// Strictly increasing per sender. `_shouldApply` drops anything with
  /// `timestamp <= _lastAppliedTimestamp`, and a wall-clock millisecond is not
  /// fine-grained enough: `_playPause` broadcasts play *and* seek in one
  /// synchronous block, so both stamped `DateTime.now()` and receivers silently
  /// dropped the second one. Every broadcast must stamp itself from here.
  int _nextTimestamp() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastIssuedTimestamp = now > _lastIssuedTimestamp ? now : _lastIssuedTimestamp + 1;
    return _lastIssuedTimestamp;
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
    _tearingDown = true;
    _reconnectTimer?.cancel();
    _driftTimer?.cancel();
    _stateRequestRetry?.cancel();
    final channel = _channel;
    _channel = null;
    await channel?.unsubscribe();
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
    _canonicalMediaController.close();
    _gateController.close();
    _kickedController.close();
    _gateResumedController.close();
    _transportLockController.close();
    _roomEndedController.close();
    _connectionController.close();
    _remoteActionController.close();
    disconnect();
  }
}
