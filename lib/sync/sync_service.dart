import 'dart:async';

import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/profile/profile_models.dart';
import 'package:playtogether/rooms/reactions.dart';
import 'package:playtogether/rooms/room_models.dart';

import 'sync_backend.dart';
import 'sync_events.dart';
import 'sync_logic.dart';
import 'sync_logic.dart' as logic;

export 'sync_backend.dart';
export 'sync_logic.dart';

/// Room-scoped sync engine over a private Supabase Realtime channel
/// (`room:<id>`). Created on room entry, disposed on leave.
///
/// Echo/loop prevention is a trio — do not break it:
/// 1. channel `self: false` — never receive own broadcasts;
/// 2. [_isApplyingRemoteAction] suppresses re-broadcast while applying;
/// 3. last-action-wins ordering in [_shouldApply].
class SyncService {
  SyncService(
    this._player, {
    required this.room,
    required this.profile,
    required String role,
    this.backend = const SupabaseSyncBackend(),
  })
    // ignore: prefer_initializing_formals
    : _role = role {
    _canonicalMedia = RoomMedia.fromRoom(room);
  }

  final SyncPlayer _player;
  final SyncBackend backend;
  final Room room;
  final Profile profile;
  String _role;

  String get userId => profile.id;
  bool get isHost => _role == 'host';

  SyncChannel? _channel;
  late final _ordering = SyncOrdering(userId: userId);
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

  bool memberSatisfiesGate(PresentMember member) =>
      logic.memberSatisfiesGate(member, _canonicalMedia);

  GateState get gateState => logic.evaluateGateState(
    hasPresenceSynced: _hasPresenceSynced,
    media: _canonicalMedia,
    members: _presentMembers,
  );

  List<PresentMember> get gateBlockers => logic.gateBlockersOf(_canonicalMedia, _presentMembers);

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
    String event,
    void Function(Map<String, dynamic>) handler,
  ) {
    return (payload) {
      try {
        handler(_unwrapPayload(payload));
      } catch (error, stack) {
        reportNonFatal(error, stack, during: 'handling a $event broadcast');
      }
    };
  }

  Future<void> connect() async {
    final channel = backend.channel('room:${room.id}');
    _channel = channel;

    void on(String event, void Function(Map<String, dynamic>) handler) {
      channel.onBroadcast(event: event, callback: _guard(event, handler));
    }

    on(SyncEventType.play, _handlePlay);
    on(SyncEventType.pause, _handlePause);
    on(SyncEventType.seek, _handleSeek);
    on(SyncEventType.stateRequest, _handleStateRequest);
    on(SyncEventType.stateResponse, _handleStateResponse);
    on(SyncEventType.modeSwitch, _handleModeSwitch);
    on(SyncEventType.chat, _handleChat);
    on(SyncEventType.typing, _handleTyping);
    on(SyncEventType.positionSync, _handlePositionSync);
    on(SyncEventType.fileInfo, _handleFileInfo);
    on(SyncEventType.mediaSet, _handleMediaSet);
    on(SyncEventType.memberKicked, _handleMemberKicked);
    on(SyncEventType.transportLock, _handleTransportLock);
    on(SyncEventType.reaction, _handleReaction);
    on(SyncEventType.roomEnded, _handleRoomEnded);

    channel.onPresenceSync(_handlePresenceSync).subscribe((status, error) {
      // Statuses from a superseded channel (reconnect replaced it) are stale.
      if (_disposed || _tearingDown || !identical(channel, _channel)) return;
      switch (status) {
        case SyncSubscribeStatus.subscribed:
          trace(
            'channel subscribed',
            category: 'sync',
            data: {'room_id': room.id, 'after_attempts': _reconnectAttempts},
          );
          _reconnectAttempts = 0;
          _connectionController.add(true);
          _trackPresence();
          _reannounceFileInfo();
          unawaited(refreshCanonicalMedia());
          _requestInitialState();
        case SyncSubscribeStatus.channelError:
        case SyncSubscribeStatus.closed:
        case SyncSubscribeStatus.timedOut:
          trace(
            'channel dropped',
            category: 'sync',
            data: {'status': status.name, 'error': error?.toString()},
          );
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
    trace(
      'scheduling a resubscribe',
      category: 'sync',
      data: {'attempt': _reconnectAttempts, 'delay_ms': delay.inMilliseconds},
    );
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
      payload: {'senderId': userId, 'timestamp': _nextTimestamp(), 'locked': locked},
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
      payload: {'senderId': userId, 'timestamp': _nextTimestamp(), 'targetUserId': targetUserId},
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
    final row = await backend.loadMembership(room.id, userId);
    if (row != null) {
      _role = row.role;
      _membershipJoinedAt = row.joinedAt;
    }
  }

  ReadyStatus _readyStatus = .none;
  String? _loadedFileName;
  bool _privacyMode = false;

  ReadyStatus get readyStatus => _readyStatus;
  String? get loadedFileName => _loadedFileName;
  bool get privacyMode => _privacyMode;

  void _trackPresence() {
    _channel?.track({
      'user_id': userId,
      'display_name': profile.displayName,
      'avatar_url': profile.avatarUrl,
      'role': _role,
      'joined_at': (_membershipJoinedAt ?? DateTime.now()).toIso8601String(),
      'ready_status': _readyStatus.wire,
      'loaded_file_name': _loadedFileName,
      'privacy_mode': _privacyMode,
    });
  }

  /// Host succession: re-announce presence with the new role.
  void updateRole(String role) {
    if (_role == role) return;
    trace('role changed', category: 'sync', data: {'from': _role, 'to': role});
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
    trace(
      'readiness ${_readyStatus.wire} -> ${status.wire}',
      category: 'gate',
      data: {'file': loadedFileName},
    );
    _readyStatus = status;
    _loadedFileName = loadedFileName;
    _trackPresence();
    _checkSelfGateSatisfaction();
  }

  void retrackPrivacy(bool enabled) {
    if (_privacyMode == enabled) return;
    trace('privacy mode ${enabled ? 'on' : 'off'}', category: 'room');
    _privacyMode = enabled;
    _trackPresence();
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
    if (_roomPlaying || _pausedByGate) {
      trace(
        'skipped the room-position resync',
        category: 'media',
        data: {'guard': _roomPlaying ? 'room_playing' : 'paused_by_gate'},
      );
      return;
    }
    // Alone in the room: nobody to answer, and our own position *is* the room's.
    if (_hasPresenceSynced && _presentMembers.every((m) => m.userId == userId)) {
      trace('skipped the room-position resync', category: 'media', data: {'guard': 'alone'});
      return;
    }
    trace('re-requesting the room position', category: 'media');
    _hasReceivedInitialState = false;
    _requestInitialState();
  }

  void _handlePresenceSync() {
    if (_disposed) return;
    final states = _channel?.presenceState();
    if (states == null) return;
    _hasPresenceSynced = true;
    _presentMembers = logic.mergePresence(states);
    _presenceController.add(_presentMembers);
    _evaluateGate();
  }

  // ---------------------------------------------------------------------------
  // Chat: rows in `messages` are the durable history; the broadcast is only
  // the low-latency fan-out. Late joiners read the table.
  // ---------------------------------------------------------------------------

  Future<List<ChatMessage>> loadChatHistory() => backend.loadChatHistory(room.id);

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
    } catch (e, s) {
      // The row below still persists it, so the message survives — but nobody
      // sees it until their next history reload.
      reportNonFatal(e, s, during: 'broadcasting a chat message');
    }
    unawaited(() async {
      try {
        await backend.insertChatMessage(roomId: room.id, senderId: userId, content: content);
      } catch (e, s) {
        // Worse than a failed broadcast: the message showed up live for
        // everyone present and then silently ceases to exist, so it is gone
        // from history after any reconnect and for every later joiner.
        reportNonFatal(e, s, during: 'persisting a chat message');
      }
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

  final _reactionController = StreamController<ReactionEvent>.broadcast();
  Stream<ReactionEvent> get reactionsStream => _reactionController.stream;

  final _reactionThrottle = ReactionThrottle();

  void sendReaction(String emoji) {
    if (_disposed) return;
    if (reactionForEmoji(emoji) == null) return;
    // Local echo is mandatory (the channel is self:false) and never throttled.
    _reactionController.add(
      ReactionEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
        emoji: emoji,
        displayName: profile.displayName,
      ),
    );
    _reactionThrottle.submit(emoji, _broadcastReaction);
  }

  void _broadcastReaction(String emoji) {
    unawaited(() async {
      try {
        await _channel?.sendBroadcastMessage(
          event: SyncEventType.reaction,
          payload: ReactionEvent(
            senderId: userId,
            timestamp: _nextTimestamp(),
            emoji: emoji,
            displayName: profile.displayName,
          ).toPayload(),
        );
      } catch (e, s) {
        reportNonFatal(e, s, during: 'broadcasting a reaction');
      }
    }());
  }

  void _handleReaction(Map<String, dynamic> payload) {
    if (_disposed) return;
    final event = ReactionEvent.fromPayload(payload);
    if (event.senderId == userId) return;
    if (reactionForEmoji(event.emoji) == null) return;
    _reactionController.add(event);
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
    if (!media.isNewerThan(_canonicalMedia)) {
      trace(
        'rejected stale canonical media',
        category: 'media',
        data: {
          'kind': media.kind.wire,
          'updated_at': media.updatedAt?.toIso8601String(),
          'current_updated_at': _canonicalMedia.updatedAt?.toIso8601String(),
        },
      );
      return;
    }
    trace(
      'adopted canonical media',
      category: 'media',
      data: {
        'kind': media.kind.wire,
        'name': media.name,
        'updated_at': media.updatedAt?.toIso8601String(),
      },
    );
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

    final transition = logic.gateTransitionFor(
      previous: previous,
      next: state,
      isAuthority: _isAuthority,
      roomPlaying: _roomPlaying,
      pausedByGate: _pausedByGate,
    );

    trace(
      'gate ${previous.name} -> ${state.name}',
      category: 'gate',
      data: {
        'blocker': gateBlocker?.userId,
        'room_playing': _roomPlaying,
        'paused_by_gate': _pausedByGate,
        'authority': _isAuthority,
        'transition': transition?.name,
      },
    );

    switch (transition) {
      case null:
        return;
      case GateTransition.pause:
        _gateHeldPosition = logic.gateHeldPosition(
          subjectUserId: gateBlocker?.userId,
          userId: userId,
          position: () => currentPosition?.call(),
        );
        trace(
          'gate paused the room',
          category: 'gate',
          data: {
            'held_position_ms': _gateHeldPosition?.inMilliseconds,
            'held_position_dropped': _gateHeldPosition == null,
          },
        );
        _pausedByGate = true;
        // Broadcast BEFORE applying: broadcastPause() bails out while
        // _isApplyingRemoteAction is set, so the reverse order sends nothing.
        unawaited(
          broadcastPause(reason: SyncActionReason.gate, subjectUserId: gateBlocker?.userId),
        );
        _applyRemoteAction(() {
          onRemotePause != null ? onRemotePause!() : _player.pause();
        });
      case GateTransition.resume:
        _pausedByGate = false;
        final resumeAt = _gateHeldPosition;
        _gateHeldPosition = null;
        trace(
          'gate resumed the room',
          category: 'gate',
          data: {'resume_position_ms': resumeAt?.inMilliseconds},
        );
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
      final fresh = await backend.fetchRoom(room.id);
      if (_disposed || fresh == null) return;
      _setTransportLock(fresh.transportLock);
      _adoptCanonicalMedia(RoomMedia.fromRoom(fresh));
    } catch (e, s) {
      // The row is the source of truth for the readiness gate, and this refetch
      // is what a reconnecting client relies on. Failing it leaves the gate
      // deciding against stale media.
      reportNonFatal(e, s, during: 'refetching canonical media for room ${room.id}');
    }
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
        duration: event.durationMs != null ? Duration(milliseconds: event.durationMs!) : null,
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
    trace('requesting the room state', category: 'sync', data: {'room_id': room.id});
    _channel?.sendBroadcastMessage(
      event: SyncEventType.stateRequest,
      payload: StateRequestEvent(senderId: userId, timestamp: _nextTimestamp()).toPayload(),
    );
    _stateRequestRetry?.cancel();
    _stateRequestRetry = Timer(const Duration(seconds: 2), () {
      if (_hasReceivedInitialState || _disposed) return;
      trace('re-requesting the room state', category: 'sync', data: {'room_id': room.id});
      _channel?.sendBroadcastMessage(
        event: SyncEventType.stateRequest,
        payload: StateRequestEvent(senderId: userId, timestamp: _nextTimestamp()).toPayload(),
      );
      // After the retry window, assume an idle room.
      _stateRequestRetry = Timer(const Duration(seconds: 2), () {
        trace('no state response — assuming an idle room', category: 'sync');
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
    privacyMode: _privacyMode,
  );

  List<PresentMember> get _authorityCandidates => [
    ..._presentMembers.where((m) => m.userId != userId),
    _selfPresence,
  ];

  bool get _isAuthority => logic.authorityAmong(_authorityCandidates) == userId;

  void _handleStateRequest(Map<String, dynamic> payload) {
    // The authority answers — except when the authority is the one asking (a
    // host reopening their own room), where the next in line answers instead.
    // Excluding the requester keeps it to exactly one responder either way.
    final requesterId = payload['senderId'] as String?;
    final responder = logic.authorityAmong(
      _authorityCandidates.where((m) => m.userId != requesterId),
    );
    if (responder != userId) return;
    final hasMedia = _player.duration != Duration.zero || _currentYoutubeUrl != null;
    if (!hasMedia) {
      trace(
        'elected to answer a state request but have no media',
        category: 'sync',
        data: {'requester': requesterId},
      );
      return;
    }

    trace(
      'answering a state request',
      category: 'sync',
      data: {
        'requester': requesterId,
        'mode': _currentMode,
        'playing': isPlaying?.call() ?? _player.playing,
        'position_ms': (currentPosition?.call() ?? _player.position).inMilliseconds,
      },
    );
    _channel?.sendBroadcastMessage(
      event: SyncEventType.stateResponse,
      payload: StateResponseEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
        playing: isPlaying?.call() ?? _player.playing,
        positionMs: (currentPosition?.call() ?? _player.position).inMilliseconds,
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
    trace(
      'applying the room state',
      category: 'sync',
      data: {
        'from': event.senderId,
        'mode': event.mode,
        'playing': event.playing,
        'position_ms': event.positionMs,
        'file': event.fileName,
      },
    );
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
        _player.seek(Duration(milliseconds: event.positionMs));
      }
      if (event.playing) {
        onRemotePlay != null ? onRemotePlay!() : _player.play();
      } else {
        onRemotePause != null ? onRemotePause!() : _player.pause();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Drift correction (host heartbeat every 10 s while playing)
  // ---------------------------------------------------------------------------

  static const _driftThreshold = Duration(milliseconds: 1500);

  void _broadcastPositionSync() {
    if (!isHost || _isApplyingRemoteAction) return;
    final playing = isPlaying?.call() ?? _player.playing;
    if (!playing) return;
    _channel?.sendBroadcastMessage(
      event: SyncEventType.positionSync,
      payload: PositionSyncEvent(
        senderId: userId,
        timestamp: _nextTimestamp(),
        positionMs: (currentPosition?.call() ?? _player.position).inMilliseconds,
        playing: playing,
      ).toPayload(),
    );
  }

  void _handlePositionSync(Map<String, dynamic> payload) {
    final event = PositionSyncEvent.fromPayload(payload);
    _roomPlaying = event.playing; // authority heartbeat keeps this honest
    final localPlaying = isPlaying?.call() ?? _player.playing;
    if (!event.playing || !localPlaying) return;
    final local = currentPosition?.call() ?? _player.position;
    final remote = Duration(milliseconds: event.positionMs);
    if ((local - remote).abs() <= _driftThreshold) return;
    trace(
      'correcting drift',
      category: 'sync',
      data: {'delta_ms': (local - remote).inMilliseconds, 'to_ms': remote.inMilliseconds},
    );
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
      _gateHeldPosition = logic.gateHeldPosition(
        subjectUserId: payload['subjectUserId'] as String?,
        userId: userId,
        position: () => currentPosition?.call(),
      );
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

  void _emitRemoteAction(
    Map<String, dynamic> payload,
    RemoteActionKind kind, [
    Duration? position,
  ]) {
    if (_disposed) return;
    _remoteActionController.add(
      RemoteAction(senderId: payload['senderId'] as String, kind: kind, position: position),
    );
  }

  void _handleModeSwitch(Map<String, dynamic> payload) {
    if (_disposed || !_shouldApply(payload)) return;
    _modeSwitchController.add(ModeSwitchEvent.fromPayload(payload));
  }

  int _nextTimestamp() => _ordering.nextTimestamp();

  bool _shouldApply(Map<String, dynamic> payload) {
    final applied = _ordering.shouldApply(payload);
    if (!applied && payload['senderId'] != userId) {
      trace(
        'dropped a stale event',
        category: 'sync',
        data: {
          'sender': payload['senderId'],
          'timestamp': payload['timestamp'],
          'last_applied': _ordering.lastApplied,
        },
      );
    }
    return applied;
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
    _reactionThrottle.dispose();
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
    _reactionController.close();
    disconnect();
  }
}
