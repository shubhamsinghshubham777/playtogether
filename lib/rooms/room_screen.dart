import 'dart:async';

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:playtogether/av/livekit_service.dart';
import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/platform.dart';
import 'package:playtogether/player/chooser_dialog.dart';
import 'package:playtogether/player/mode_selection_dialog.dart';
import 'package:playtogether/player/youtube_url_dialog.dart';
import 'package:playtogether/profile/profile_service.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/rooms/room_service.dart';
import 'package:playtogether/rooms/widgets/facecam_rail.dart';
import 'package:playtogether/rooms/widgets/kick_member_dialog.dart';
import 'package:playtogether/rooms/widgets/readiness_overlay.dart';
import 'package:playtogether/rooms/widgets/room_chat_panel.dart';
import 'package:playtogether/rooms/widgets/room_control_bar.dart';
import 'package:playtogether/rooms/widgets/room_overflow_menu.dart';
import 'package:playtogether/sync/sync_events.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:playtogether/ui/banners.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/pt_motion.dart';
import 'package:playtogether/ui/pt_theme.dart';
import 'package:playtogether/ui/responsive.dart';
import 'package:window_manager/window_manager.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as yt;

enum PlaybackMode { local, youtube }

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.roomId, required this.player});

  final String roomId;
  final Player player;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> with WindowListener, TickerProviderStateMixin {
  late final controller = VideoController(widget.player);

  Room? _room;
  SyncService? _sync;
  LiveKitService? _av;
  List<RoomMember> _members = const [];
  List<PresentMember> _present = const [];
  bool _loading = true;

  PlaybackMode _mode = .local;
  String? _youtubeUrl;
  yt.YoutubePlayerController? _youtubeController;
  bool _youtubeWasPlaying = false;
  // YT sync uses an *intent* model: `seekTo` in youtube_player_flutter always
  // calls play(), and iframe state transitions land 200-500 ms after commands
  // (far outside SyncService's 100 ms settle window). `_ytIntendedPlaying` is
  // the agreed play state; the player listener only broadcasts transitions
  // that DIVERGE from it (i.e. the user acted on the iframe directly).
  bool _ytIntendedPlaying = false;
  // Remote commands that arrive before the iframe is ready are queued and
  // flushed on the first ready event (late-joiner state_response).
  Duration? _pendingYtSeek;
  bool? _pendingYtPlay;
  // Ignore the transient playing-blip caused by seekTo-then-pause.
  DateTime _ytEventSuppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isModeSelectionDialogOpen = false;
  bool _isYouTubeUrlDialogOpen = false;
  // A remote mode_switch popping the URL dialog must not trip the
  // "cancelled and still idle: re-ask" fallback.
  bool _urlDialogDismissedRemotely = false;

  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;

  final _messages = <ChatMessage>[];
  List<String> _typingNames = const [];
  bool _chatOpen = false;
  int _unread = 0;
  bool _camsVisible = true;

  // Drives the chat panel's slide+fade in the overlay layouts *and* the
  // cross-fade of what it covers (facecam rail, floating bubbles), so the two
  // halves of the swap stay in lockstep. `_chatOpen` flips immediately; the
  // panel is what lags behind it.
  static const _chatMotion = Durations.medium1;
  late final AnimationController _chatAnim = AnimationController(
    vsync: this,
    duration: _chatMotion,
  );
  late final CurvedAnimation _chatCurve = CurvedAnimation(
    parent: _chatAnim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  // Attribution toast for remote play/pause/seek ("«name» jumped to 12:40") so
  // playback jumps don't read as glitches. Kept mounted (text persists) while
  // it fades so the fade-out actually renders.
  String _actionToastText = '';
  bool _actionToastVisible = false;
  bool _actionToastArrival = false;
  Timer? _actionToastTimer;

  // Floating chat bubbles (last 3) shown over the video while the panel is
  // closed (desktop/landscape only — portrait chat is always visible). Each
  // self-expires; timers are tracked so they can be cancelled on dispose, and
  // on open (where the bubbles instead fade out under the arriving panel).
  final _overlayChat = <ChatMessage>[];
  final _overlayChatTimers = <Timer>{};

  /// Bubbles that have timed out and are playing their exit. They stay in
  /// [_overlayChat] until the fade finishes — removing them on the timer alone
  /// is what made them vanish mid-sentence.
  final _expiringChat = <ChatMessage>{};

  // Double-tap skip feedback (touch layouts): -1 flashes the left −10s label,
  // 1 the right +10s, 0 none.
  int _skipFlash = 0;
  Timer? _skipFlashTimer;

  // OS-window fullscreen (desktop only). Kept in sync with the actual window
  // via WindowListener so Esc/toggle never desync from a native fullscreen.
  bool _fullscreen = false;

  // Floating chrome (topbar + control bar) auto-hides while playing; tap the
  // video to toggle it manually. Only applies to the overlay layouts
  // (desktop/landscape) — portrait keeps controls in the column flow.
  bool _controlsVisible = true;
  bool _pointerOverControls = false;
  Timer? _controlsHideTimer;
  double _volumeBeforeMute = 1.0;
  final _shortcutFocus = FocusNode();

  Timer? _countdownTimer;
  Duration _timeLeft = Duration.zero;
  bool _warningDismissed = false;
  bool _connected = true;
  bool _ended = false;
  Timer? _idleSourceTimer;
  // True until the first source decision lands (the chooser opens, or a remote
  // mode_switch beats it): keeps the video area in its loading state instead of
  // showing an empty black frame for the whole state-sync window. One-shot.
  bool _awaitingFirstSource = true;

  RoomMedia _canonicalMedia = RoomMedia.none;
  String? _localFileName;
  bool _mismatchDismissed = false;

  // Own readiness inputs. `_updateReadiness` derives a ReadyStatus from these
  // and pushes it onto presence, which is what the gate reads.
  bool _isFilePickerOpen = false;
  bool _ytBufferReady = false;
  Timer? _ytBufferFallbackTimer;
  int _ytDurationProbeGen = 0;

  GateState _gateState = GateState.indeterminate;

  // Readiness-overlay reveal. Driven only by `closed` — `indeterminate` must
  // render as usable, or the overlay flashes on every room entry. Out is
  // quicker than in on purpose: the payoff of the gate opening is *seeing the
  // video*, so don't make people wait for it.
  late final AnimationController _gateAnim = AnimationController(
    vsync: this,
    duration: PTMotion.panel,
    reverseDuration: PTMotion.state,
  );
  late final CurvedAnimation _gateCurve = CurvedAnimation(
    parent: _gateAnim,
    curve: PTMotion.enter,
    reverseCurve: PTMotion.exit,
  );

  /// The overlay is suppressed until the first source decision lands, so
  /// clearing that flag is also a gate-visibility edge.
  void _resolveFirstSource() {
    setState(() => _awaitingFirstSource = false);
    _syncGateReveal();
  }

  void _syncGateReveal() {
    final shouldShow = _gateState == GateState.closed && !_awaitingFirstSource;
    if (shouldShow) {
      _gateAnim.forward();
    } else {
      _gateAnim.reverse();
    }
  }

  // The overflow menu is a Navigator route — a sibling subtree — so setState
  // here can never rebuild it. Everything it shows is pushed through this
  // notifier instead; null means "close now" (the room is over for us).
  final _menuData = ValueNotifier<RoomMenuData?>(null);

  /// The room's canonical local file. Derived from [_canonicalMedia] rather
  /// than from whoever last broadcast `file_info`, so it survives host
  /// succession and is already correct for a late joiner.
  ({String name, Duration duration})? get _roomFile {
    if (_canonicalMedia.kind != .local) return null;
    final name = _canonicalMedia.name;
    if (name == null) return null;
    return (name: name, duration: _canonicalMedia.duration ?? Duration.zero);
  }

  final _subscriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    if (isDesktop) {
      windowManager.addListener(this);
      // The window is already fullscreen by the time the first room opens (the
      // app launches that way), and the listener only reports *transitions* —
      // without seeding, Esc would fall through to nothing.
      windowManager.isFullScreen().then((value) {
        if (mounted && value != _fullscreen) setState(() => _fullscreen = value);
      });
    }
    // Bubbles are kept alive (fading) until the panel has fully covered them.
    _chatAnim.addStatusListener((status) {
      if (status == AnimationStatus.completed && _overlayChat.isNotEmpty) {
        setState(() {
          _overlayChat.clear();
          _expiringChat.clear();
        });
      }
    });
    _init();
  }

  @override
  void onWindowEnterFullScreen() => setState(() => _fullscreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullscreen = false);

  Future<void> _init() async {
    // The Player is app-wide and outlives this screen, so it still holds
    // whatever the previous room opened. Unload before anything subscribes to
    // its streams. Done on entry, not in dispose(): swapping /room/A for
    // /room/B runs the new State's initState *before* the old one's dispose,
    // so clearing on the way out would wipe the room being entered.
    await widget.player.stop();

    final profile = ProfileService.instance.profile ?? await ProfileService.instance.load();
    if (profile == null) {
      if (mounted) context.go('/login');
      return;
    }

    // A transient fetch failure must NOT be misread as "room ended" —
    // only a missing/expired room gets the "That's a wrap!" treatment.
    Room? room;
    var loadFailed = false;
    try {
      room = await RoomService.instance.fetchRoom(widget.roomId);
      await RoomService.instance.syncServerTime();
    } catch (e, s) {
      loadFailed = true;
      // The user gets a deliberately vague "check your connection"; the log is
      // the only place the actual cause (RLS, expiry, network) survives.
      reportNonFatal(e, s, during: 'loading room ${widget.roomId}');
    }
    if (!mounted) return;
    if (loadFailed) {
      _snack("Couldn't load the room — check your connection and try again.");
      context.go('/lobby');
      return;
    }
    if (room == null ||
        room.endedAt != null ||
        room.expiresAt.isBefore(RoomService.instance.serverNow)) {
      _showEndedDialog();
      return;
    }

    try {
      _members = await RoomService.instance.fetchMembers(widget.roomId);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'loading members of room ${widget.roomId}');
      if (mounted) {
        _snack("Couldn't load the room — check your connection and try again.");
        context.go('/lobby');
      }
      return;
    }
    final selfMembership = _members.where((m) => m.userId == profile.id).firstOrNull;
    if (selfMembership == null) {
      // RLS would have hidden the room if we weren't a member; defensive.
      if (mounted) context.go('/lobby');
      return;
    }

    final sync = SyncService(
      widget.player,
      room: room,
      profile: profile,
      role: selfMembership.role,
    );
    await sync.loadMembership();

    sync.onRemotePlay = _remotePlay;
    sync.onRemotePause = _remotePause;
    sync.onRemoteSeek = _remoteSeek;
    sync.onRemoteDriftCorrect = _remoteDriftCorrect;
    sync.currentPosition = () => _position;
    sync.isPlaying = () => _playing;

    _subscriptions.addAll([
      sync.chatMessages.listen((message) {
        setState(() {
          _messages.add(message);
          if (!_chatOpen) _unread++;
        });
        if (!_chatOpen) _pushOverlayChat(message);
      }),
      sync.typingStream.listen((names) => setState(() => _typingNames = names)),
      sync.presenceStream.listen(_onPresenceChanged),
      sync.remoteActions.listen(_onRemoteAction),
      sync.modeSwitchStream.listen(_onRemoteModeSwitch),
      sync.canonicalMediaStream.listen(_onCanonicalMedia),
      sync.gateStream.listen((state) {
        setState(() => _gateState = state);
        _syncGateReveal();
      }),
      sync.roomEndedStream.listen((_) => _onRoomEnded()),
      sync.kickedStream.listen((_) => _onKicked()),
      sync.transportLockStream.listen((_) {
        setState(() {});
        _publishMenuData();
      }),
      sync.gateResumedStream.listen(
        (_) => _showActionToast("Everyone's ready — resuming", arrival: true),
      ),
      sync.connectionStream.listen((up) {
        final wasConnected = _connected;
        setState(() => _connected = up);
        // Backfill anything said during the outage — broadcasts don't replay.
        if (up && !wasConnected) _reloadChatHistory();
      }),
      widget.player.stream.playing.listen((playing) {
        if (_mode == .local) {
          setState(() => _playing = playing);
          _onPlayingChangedForControls(playing);
        }
      }),
      widget.player.stream.position.listen((position) {
        if (_mode == .local) setState(() => _position = position);
      }),
      widget.player.stream.duration.listen((duration) {
        if (_mode != .local) return;
        setState(() => _duration = duration);
        // A non-zero duration is what "the file is actually open" means, so
        // this is the local-mode loading -> ready edge.
        _updateReadiness();
      }),
      widget.player.stream.buffering.listen((buffering) {
        if (_mode == .local) setState(() => _buffering = buffering);
      }),
      widget.player.stream.volume.listen((volume) => setState(() => _volume = volume / 100)),
    ]);

    setState(() {
      _room = room;
      _sync = sync;
      _canonicalMedia = sync.canonicalMedia;
      _loading = false;
    });

    await sync.connect();
    _updateReadiness();
    unawaited(_reloadChatHistory());

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
    _tickCountdown();

    // If the state-sync window closes with no media, we're first in — ask
    // what to watch.
    _idleSourceTimer = Timer(const Duration(milliseconds: 4500), () {
      if (!mounted) return;
      _resolveFirstSource();
      if (_ended) return;
      // Members are never auto-prompted for a source — the readiness overlay
      // tells them the host is still choosing.
      if (!(_sync?.isHost ?? false)) return;
      final hasMedia = widget.player.state.duration != Duration.zero || _youtubeUrl != null;
      if (!hasMedia && !_isModeSelectionDialogOpen && !_isYouTubeUrlDialogOpen) {
        _showModeSelectionDialog();
      }
    });

    if (LiveKitService.isConfigured) {
      final av = LiveKitService(roomId: widget.roomId);
      setState(() => _av = av);
      av.connect().catchError((_) {});
    }
  }

  @override
  void dispose() {
    if (isDesktop) windowManager.removeListener(this);
    for (final s in _subscriptions) {
      s.cancel();
    }
    _countdownTimer?.cancel();
    _idleSourceTimer?.cancel();
    _controlsHideTimer?.cancel();
    _actionToastTimer?.cancel();
    _skipFlashTimer?.cancel();
    _ytBufferFallbackTimer?.cancel();
    for (final t in _overlayChatTimers) {
      t.cancel();
    }
    _shortcutFocus.dispose();
    _menuData.dispose();
    _chatCurve.dispose();
    _chatAnim.dispose();
    _gateCurve.dispose();
    _gateAnim.dispose();
    _youtubeController?.dispose();
    _sync?.dispose();
    _av?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Presence / membership
  // ---------------------------------------------------------------------------

  Future<void> _onPresenceChanged(List<PresentMember> present) async {
    setState(() => _present = present);
    // Don't wait on the member fetch: readiness/online changes should land in
    // an open menu immediately, even if the round-trip is slow or fails.
    _publishMenuData();
    // Membership can change under us (join/leave/host succession).
    try {
      final members = await RoomService.instance.fetchMembers(widget.roomId);
      if (!mounted) return;
      setState(() => _members = members);
      final selfRole = members.where((m) => m.userId == _sync?.userId).firstOrNull?.role;
      if (selfRole != null) {
        final wasHost = _sync?.isHost ?? false;
        _sync?.updateRole(selfRole);
        // Inheriting an empty room means inheriting the job of choosing (D2).
        // The original 4.5 s idle prompt is one-shot and long gone by now.
        if (!wasHost &&
            (_sync?.isHost ?? false) &&
            !_canonicalMedia.isSet &&
            !_ended &&
            !_isModeSelectionDialogOpen &&
            !_isYouTubeUrlDialogOpen) {
          _showModeSelectionDialog();
        }
      }
      _publishMenuData();
    } catch (e, s) {
      // Presence still landed; only the membership refresh behind it failed.
      // The cost is a stale roster: a host succession we didn't notice, or a
      // kick the overflow menu keeps showing.
      reportNonFatal(e, s, during: 'refreshing members after a presence change');
    }
  }

  /// Republish the overflow menu's snapshot. Cheap and idempotent (nothing
  /// listens while the menu is closed), so call it from anywhere any of its
  /// inputs move: presence, membership, own role, canonical media, transport
  /// lock, eviction.
  void _publishMenuData() {
    final sync = _sync;
    _menuData.value = _ended
        ? null
        : RoomMenuData(
            members: _members,
            present: _present,
            media: _canonicalMedia,
            transportLock: sync?.transportLock ?? false,
            selfId: sync?.userId ?? '',
            selfIsHost: sync?.isHost ?? false,
          );
  }

  void _onRemoteAction(RemoteAction action) {
    final name =
        _present.where((m) => m.userId == action.senderId).firstOrNull?.displayName ??
        _members.where((m) => m.userId == action.senderId).firstOrNull?.displayName ??
        'Someone';
    _showActionToast(switch (action.kind) {
      RemoteActionKind.seek => '$name jumped to ${_clock(action.position ?? Duration.zero)}',
      RemoteActionKind.play => '$name resumed the video',
      RemoteActionKind.pause => '$name paused the video',
    });
  }

  /// [arrival] gets the one overshoot curve in the system — reserved for
  /// "we're all here" moments, never for routine attribution.
  void _showActionToast(String text, {bool arrival = false}) {
    if (!mounted) return;
    setState(() {
      _actionToastText = text;
      _actionToastVisible = true;
      _actionToastArrival = arrival;
    });
    _actionToastTimer?.cancel();
    _actionToastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _actionToastVisible = false);
    });
  }

  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _pushOverlayChat(ChatMessage message) {
    setState(() {
      _overlayChat.add(message);
      if (_overlayChat.length > 3) _expiringChat.remove(_overlayChat.removeAt(0));
    });
    late final Timer timer;
    timer = Timer(const Duration(seconds: 5), () {
      _overlayChatTimers.remove(timer);
      if (!mounted) return;
      setState(() => _expiringChat.add(message));
      late final Timer removal;
      removal = Timer(PTMotion.state, () {
        _overlayChatTimers.remove(removal);
        if (!mounted) return;
        setState(() {
          _overlayChat.remove(message);
          _expiringChat.remove(message);
        });
      });
      _overlayChatTimers.add(removal);
    });
    _overlayChatTimers.add(timer);
  }

  void _cancelOverlayChatTimers() {
    for (final t in _overlayChatTimers) {
      t.cancel();
    }
    _overlayChatTimers.clear();
    _expiringChat.clear();
  }

  // ---------------------------------------------------------------------------
  // Remote playback routing (dual player)
  // ---------------------------------------------------------------------------

  bool get _ytReady => _youtubeController?.value.isReady ?? false;

  /// Spinner shows only while the player is stalled AND meant to be playing —
  /// a buffer that fills behind a paused frame needs no indicator. YouTube's
  /// state reads `buffering` (not `playing`) mid-stall, so gate it on intent.
  bool get _showBuffering => _buffering && (_mode == .youtube ? _ytIntendedPlaying : _playing);

  void _remotePlay() {
    if (_mode == .youtube) {
      _ytIntendedPlaying = true;
      if (!_ytReady) {
        _pendingYtPlay = true;
        return;
      }
      _youtubeController?.play();
    } else {
      widget.player.play();
    }
  }

  void _remotePause() {
    if (_mode == .youtube) {
      _ytIntendedPlaying = false;
      if (!_ytReady) {
        _pendingYtPlay = false;
        return;
      }
      _youtubeController?.pause();
    } else {
      widget.player.pause();
    }
  }

  void _remoteSeek(Duration position) {
    if (_mode == .youtube) {
      if (!_ytReady) {
        _pendingYtSeek = position;
        return;
      }
      _ytSeekKeepingPlayState(position);
    } else {
      widget.player.seek(position);
    }
  }

  /// seekTo always play()s (youtube_player_flutter); restore the intended
  /// pause and swallow the transient playing blip so it isn't re-broadcast.
  void _ytSeekKeepingPlayState(Duration position) {
    final controller = _youtubeController;
    if (controller == null) return;
    controller.seekTo(position);
    if (!_ytIntendedPlaying) {
      _ytEventSuppressUntil = DateTime.now().add(const Duration(milliseconds: 800));
      controller.pause();
    }
  }

  void _remoteDriftCorrect(Duration position) {
    if (_mode == .youtube) {
      // No pause: drift correction only fires while both sides are playing.
      if (_ytReady) _youtubeController?.seekTo(position);
    } else {
      widget.player.seek(position);
    }
  }

  // ---------------------------------------------------------------------------
  // Mode switching (ported from PTVideoPlayer — dialog dismissal is delicate)
  // ---------------------------------------------------------------------------

  Future<void> _onRemoteModeSwitch(dynamic event) async {
    if (mounted) {
      if (_awaitingFirstSource) _resolveFirstSource();
      // URL dialog sits on top of the source chooser; pop in that order.
      if (_isYouTubeUrlDialogOpen) {
        _urlDialogDismissedRemotely = true;
        Navigator.of(context).pop();
        _isYouTubeUrlDialogOpen = false;
      }
      if (_isModeSelectionDialogOpen) {
        Navigator.of(context).pop();
        _isModeSelectionDialogOpen = false;
      }
    }
    final PlaybackMode mode = event.mode == 'youtube' ? .youtube : .local;
    if (mode == .youtube && event.youtubeUrl != null) {
      _switchToYouTubeMode(event.youtubeUrl as String);
    } else {
      await _switchToLocalMode();
    }
  }

  Future<void> _showModeSelectionDialog() async {
    _isModeSelectionDialogOpen = true;
    _updateReadiness();
    if (_awaitingFirstSource) _resolveFirstSource();
    final mode = await showGlassDialog<InitialMode>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ModeSelectionDialog(),
    );
    _isModeSelectionDialogOpen = false;
    _updateReadiness();
    if (!mounted) return;

    if (mode == InitialMode.local) {
      await _pickVideo();
    } else if (mode == InitialMode.youtube) {
      _isYouTubeUrlDialogOpen = true;
      _urlDialogDismissedRemotely = false;
      _updateReadiness();
      final url = await showGlassDialog<String>(
        context: context,
        width: 440,
        builder: (_) => const YouTubeUrlDialog(),
      );
      _isYouTubeUrlDialogOpen = false;
      _updateReadiness();
      if (!mounted) return;
      if (url != null) {
        await _handleModeSwitch(.youtube, url);
      } else if (!_urlDialogDismissedRemotely &&
          _mode == .local &&
          widget.player.state.duration == Duration.zero) {
        _showModeSelectionDialog(); // cancelled and still idle: re-ask
      }
    }
  }

  String? _extractVideoId(String url) {
    final patterns = [
      RegExp(r'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'm\.youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  void _switchToYouTubeMode(String url) {
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      _snack("Hmm, that doesn't look like a YouTube link.");
      return;
    }
    // Re-applying the video we already have embedded must NOT rebuild the
    // player. `YoutubePlayer` binds its controller in initState and never
    // rebinds (didUpdateWidget only moves the listener), so a fresh controller
    // behind a reused element drives a disposed one: onReady never arrives,
    // `_ytReady` stays false, and transport silently dies with no duration.
    // Duplicate switches are routine — a `state_response` after a reconnect
    // replays the room's mode.
    if (_mode == .youtube &&
        _youtubeController != null &&
        _extractVideoId(_youtubeUrl ?? '') == videoId) {
      _youtubeUrl = url;
      _sync?.updatePlaybackState('youtube', url);
      _probeYtDuration(_youtubeController!);
      _updateReadiness();
      return;
    }

    // A new embed re-runs the D6 buffer race from scratch.
    _ytBufferFallbackTimer?.cancel();
    _ytBufferFallbackTimer = null;
    _ytBufferReady = false;
    setState(() {
      _mode = .youtube;
      _youtubeUrl = url;
      _localFileName = null;
      _playing = false;
      _buffering = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _youtubeWasPlaying = false;
      _ytIntendedPlaying = false;
      _pendingYtSeek = null;
      _pendingYtPlay = null;

      _youtubeController?.dispose();
      _youtubeController = yt.YoutubePlayerController(
        initialVideoId: videoId,
        flags: const yt.YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          hideThumbnail: true,
          enableCaption: true,
          captionLanguage: 'English',
          forceHD: true,
        ),
      );
      _youtubeController!.addListener(_onYouTubePlayerEvent);
    });
    _sync?.updatePlaybackState('youtube', url);
    _armYouTubeReadyFallback();
    _probeYtDuration(_youtubeController!);
    _updateReadiness();
  }

  /// The embed only pushes VideoData (duration, title) on the *playing*
  /// transition, so a cued-but-idle player sits at 00:00 until someone presses
  /// play. Pull it instead: the iframe's `getDuration()` is valid from cue
  /// time, so poll it through the underlying webview until it lands. The
  /// VideoData path still runs on first play and agrees with what we fetched.
  Future<void> _probeYtDuration(yt.YoutubePlayerController controller) async {
    final gen = ++_ytDurationProbeGen;
    for (var attempt = 0; attempt < 15; attempt++) {
      if (!mounted || gen != _ytDurationProbeGen || _youtubeController != controller) {
        return;
      }
      if (_mode != .youtube || _duration != Duration.zero) return;
      final web = controller.value.webViewController;
      if (web != null) {
        Object? result;
        try {
          // `player` doesn't exist until the iframe API has booted; guard in JS
          // so early probes return 0 instead of throwing.
          result = await web.evaluateJavascript(
            source:
                "typeof player !== 'undefined' && player.getDuration ? player.getDuration() : 0",
          );
        } catch (_) {
          // Silent by design, unlike the reported catches elsewhere: this is a
          // retrying poll, and a throw here just means the webview isn't up yet.
        }
        if (!mounted || gen != _ytDurationProbeGen || _youtubeController != controller) {
          return;
        }
        final seconds = switch (result) {
          final num n => n.toDouble(),
          final String s => double.tryParse(s) ?? 0,
          _ => 0.0,
        };
        if (seconds > 0) {
          setState(() => _duration = Duration(milliseconds: (seconds * 1000).round()));
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _switchToLocalMode() async {
    _ytBufferFallbackTimer?.cancel();
    _ytBufferFallbackTimer = null;
    _ytBufferReady = false;
    setState(() {
      _mode = .local;
      _youtubeUrl = null;
      _youtubeWasPlaying = false;
      _ytIntendedPlaying = false;
      _pendingYtSeek = null;
      _pendingYtPlay = null;
      _youtubeController?.dispose();
      _youtubeController = null;
      _playing = widget.player.state.playing;
      _buffering = widget.player.state.buffering;
      _position = widget.player.state.position;
      _duration = widget.player.state.duration;
    });
    _sync?.updatePlaybackState('local', null);
    _updateReadiness();
    await _pickVideo();
  }

  void _onYouTubePlayerEvent() {
    final controller = _youtubeController;
    if (controller == null) return;

    _flushPendingYtCommands(controller);
    _updateYouTubeReadiness(controller);

    final state = controller.value.playerState;
    final isPlaying = state == .playing;

    final wasPlaying = _playing;
    setState(() {
      _playing = isPlaying;
      _buffering = state == .buffering;
      _position = controller.value.position;
      final meta = controller.metadata.duration;
      if (meta != Duration.zero) _duration = meta;
    });
    if (isPlaying != wasPlaying) _onPlayingChangedForControls(isPlaying);

    // Broadcast only transitions that diverge from the agreed play state —
    // those are direct iframe interactions. Everything triggered by _playPause
    // or a remote event already matches _ytIntendedPlaying, so no echo and no
    // double-broadcast, regardless of iframe latency.
    final suppressed = DateTime.now().isBefore(_ytEventSuppressUntil);
    if (isPlaying && !_youtubeWasPlaying) {
      _youtubeWasPlaying = true;
      if (!_ytIntendedPlaying && !suppressed) {
        _ytIntendedPlaying = true;
        _sync?.broadcastPlay();
        _sync?.broadcastSeek(controller.value.position, reason: SyncActionReason.transport);
      }
    } else if (!isPlaying && _youtubeWasPlaying && state == .paused) {
      _youtubeWasPlaying = false;
      if (_ytIntendedPlaying && !suppressed) {
        _ytIntendedPlaying = false;
        _sync?.broadcastPause();
      }
    }

    if (controller.value.hasError) {
      _snack('Failed to load that YouTube video.');
    }
  }

  /// Late joiners get the room's position/play state before the iframe can
  /// accept commands; apply the queued state on the first ready tick.
  void _flushPendingYtCommands(yt.YoutubePlayerController controller) {
    if (!controller.value.isReady) return;
    final seek = _pendingYtSeek;
    final play = _pendingYtPlay;
    if (seek == null && play == null) return;
    _pendingYtSeek = null;
    _pendingYtPlay = null;
    if (seek != null) {
      _ytSeekKeepingPlayState(seek);
    }
    if (play == true) {
      controller.play();
    } else if (play == false && seek == null) {
      controller.pause();
    }
  }

  Future<void> _handleModeSwitch(PlaybackMode targetMode, String? url) async {
    if (targetMode == .youtube) {
      if (url != null) {
        _switchToYouTubeMode(url);
        _sync?.broadcastModeSwitch('youtube', url);
        unawaited(_publishCanonicalMedia(.youtube, url: url));
      }
    } else {
      // Clear canonical first: between leaving YouTube and actually picking a
      // file there is nothing to load, and leaving the old media set would have
      // the gate judging everyone against a video the room has moved off.
      // `_announceLocalFile` sets the real one if a file gets picked.
      await _publishCanonicalMedia(.none);
      await _switchToLocalMode();
      _sync?.broadcastModeSwitch('local', null);
    }
  }

  Future<void> _handleSwitchSource() async {
    if (_mode == .local) {
      _isYouTubeUrlDialogOpen = true;
      _updateReadiness();
      final url = await showGlassDialog<String>(
        context: context,
        width: 440,
        builder: (_) => const YouTubeUrlDialog(),
      );
      _isYouTubeUrlDialogOpen = false;
      _updateReadiness();
      if (url != null && mounted) await _handleModeSwitch(.youtube, url);
    } else {
      await _handleModeSwitch(.local, null);
    }
  }

  Future<void> _pickVideo() async {
    const videoTypeGroup = XTypeGroup(label: 'Videos', extensions: ['mp4', 'mkv']);
    _isFilePickerOpen = true;
    _updateReadiness();
    final FastFilePickerPath? response;
    try {
      response = await FastFilePicker.pickFile(acceptedTypeGroups: [videoTypeGroup]);
    } finally {
      _isFilePickerOpen = false;
    }
    final uri = response?.uri ?? response?.path;
    if (uri == null) {
      _updateReadiness(); // cancelled: back to whatever we had before
      return;
    }
    await widget.player.open(Media(uri), play: false);
    final name = _basename(response!);
    _localFileName = name;
    _mismatchDismissed = false;
    unawaited(_announceLocalFile(name));
    setState(() {});
    _updateReadiness();
  }

  /// The display name AND the gate's identity for a picked file, so it has to
  /// be stable across platforms. `path` is already human-readable; `uri` is
  /// percent-encoded (`Movie%20(2005).mkv`), which is both ugly on screen and
  /// a false mismatch against a peer whose picker returned a plain path.
  String _basename(FastFilePickerPath response) {
    final path = response.path;
    if (path != null) return path.split(RegExp(r'[/\\]')).last;
    final last = (response.uri ?? '').split(RegExp(r'[/\\]')).last;
    try {
      return Uri.decodeComponent(last);
    } catch (_) {
      return last; // a stray '%' that isn't an escape sequence
    }
  }

  /// Duration only arrives async after `open`. If it never does, announce
  /// without it rather than never announcing at all — silence would leave the
  /// room with no canonical media and the gate shut forever.
  Future<void> _announceLocalFile(String name) async {
    var duration = Duration.zero;
    try {
      duration = await widget.player.stream.duration
          .firstWhere((d) => d != Duration.zero)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Silent by design: the timeout *is* the fallback path described above.
    }
    if (!mounted) return;
    await _sync?.broadcastFileInfo(name, duration);
    await _publishCanonicalMedia(
      .local,
      name: name,
      duration: duration == Duration.zero ? null : duration,
    );
  }

  /// Host only — the RPC rejects everyone else, so this no-ops for members
  /// (whose picker exists to locate their own copy, not to set the room's).
  /// Persist first: the row is what reaches late joiners and outlives the host.
  Future<void> _publishCanonicalMedia(
    RoomMediaKind kind, {
    String? name,
    Duration? duration,
    String? url,
  }) async {
    final sync = _sync;
    if (sync == null || !sync.isHost) return;
    try {
      final room = await RoomService.instance.setRoomMedia(
        roomId: widget.roomId,
        kind: kind,
        name: name,
        duration: duration,
        url: url,
      );
      if (!mounted) return;
      await sync.broadcastMediaSet(RoomMedia.fromRoom(room));
    } catch (e) {
      if (mounted) _snack(RoomErrorCode.fromError(e).message);
    }
  }

  void _onCanonicalMedia(RoomMedia media) {
    // `media_set` and its `mode_switch` are separate broadcasts and can land in
    // either order. Drop our YouTube buffer flag the moment the room's video
    // changes, or the gate reads "ready" for the *previous* video for a beat —
    // long enough to auto-resume into the wrong thing.
    if (!_isSameYouTubeVideo(media)) {
      _ytBufferFallbackTimer?.cancel();
      _ytBufferFallbackTimer = null;
      _ytBufferReady = false;
      // Re-arm, or a reset that lands after the embed went idle would strand
      // us on "Loading" with nothing left to flip it.
      if (media.kind == .youtube && _youtubeController != null) {
        _armYouTubeReadyFallback();
      }
    }
    setState(() {
      _canonicalMedia = media;
      _mismatchDismissed = false;
    });
    _publishMenuData();
    _updateReadiness();
  }

  // ---------------------------------------------------------------------------
  // Readiness: derive our own status from local state and push it onto
  // presence. Cheap to call from anywhere — retrackReadiness no-ops when
  // nothing actually changed.
  // ---------------------------------------------------------------------------

  void _updateReadiness() {
    _sync?.retrackReadiness(
      _computeReadiness(),
      loadedFileName: _mode == .local ? _localFileName : null,
    );
  }

  ReadyStatus _computeReadiness() {
    if (_isModeSelectionDialogOpen || _isYouTubeUrlDialogOpen || _isFilePickerOpen) {
      return .selecting;
    }
    switch (_canonicalMedia.kind) {
      case .none:
        return .none; // nothing has been picked for the room yet
      case .local:
        if (_localFileName == null) return .none;
        // `ready` means "a file is fully open", NOT "the right file" — the gate
        // compares loadedFileName against canonical itself, so the UI can tell
        // "still loading" apart from "loaded the wrong thing".
        return _duration == Duration.zero ? .loading : .ready;
      case .youtube:
        return _ytBufferReady ? .ready : .loading;
    }
  }

  /// D6, amended: `cued` counts as ready. `buffered` can never rise for a
  /// member who hasn't pressed play — the package's VideoTime poll (the only
  /// thing that updates it) starts on the *playing* transition — so gating on
  /// "first buffer" sent every idle member to the 10 s fallback. Cued is the
  /// iframe's own "video fetched, can start on command", lands a beat after
  /// onReady, and is the YouTube equivalent of a local file being open.
  /// `buffered > 0` stays as an extra path for embeds that skip the cued state.
  void _updateYouTubeReadiness(yt.YoutubePlayerController controller) {
    if (_ytBufferReady) return;
    final value = controller.value;
    final state = value.playerState;
    final loaded =
        state == .cued ||
        state == .buffering ||
        state == .playing ||
        state == .paused ||
        value.buffered > 0;
    if (!value.isReady || !loaded) return;
    _ytBufferFallbackTimer?.cancel();
    _ytBufferFallbackTimer = null;
    _ytBufferReady = true;
    _updateReadiness();
  }

  /// Whether canonical media is the video this client already has embedded.
  /// Compared by **video id**, not raw URL: canonical is whatever
  /// `set_room_media` stored (trimmed, capped), while `_youtubeUrl` is the raw
  /// string `mode_switch` carried, so the two are routinely not
  /// string-identical for the same video. Treating that as a video change
  /// wiped readiness on members who had already loaded it.
  bool _isSameYouTubeVideo(RoomMedia media) {
    if (media.kind != .youtube) return false;
    final current = _youtubeUrl;
    if (current == null) return false;
    final canonicalId = _extractVideoId(media.url ?? '');
    return canonicalId != null && canonicalId == _extractVideoId(current);
  }

  /// The D6 fallback, armed when the embed is created rather than from the
  /// player listener. The controller only notifies on value *changes*, so a
  /// member who never presses play gets a short burst of events during init
  /// and then silence — arming from the listener meant that if the flag was
  /// ever cleared afterwards, nothing existed to re-arm it and they sat on
  /// "Loading" forever while the host (whose player keeps emitting) went ready.
  void _armYouTubeReadyFallback() {
    _ytBufferFallbackTimer?.cancel();
    _ytBufferFallbackTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || _ytBufferReady) return;
      _ytBufferReady = true;
      _updateReadiness();
    });
  }

  /// The old "different file loaded" banner is gone — the readiness overlay
  /// now says who is missing what, in better words, and the gate stops
  /// playback outright. What survives is the case the gate deliberately does
  /// NOT block on: right name, suspiciously different length (D3's soft
  /// warning). Non-gating by design, so it stays dismissible.
  bool get _durationDrifts {
    final roomFile = _roomFile;
    if (_mode != .local || roomFile == null || _mismatchDismissed) return false;
    if (_localFileName != roomFile.name) return false;
    return _duration != Duration.zero &&
        roomFile.duration != Duration.zero &&
        (_duration - roomFile.duration).abs() > const Duration(seconds: 2);
  }

  // ---------------------------------------------------------------------------
  // User playback actions (act locally + broadcast; play/pause also seek)
  // ---------------------------------------------------------------------------

  /// Non-host while the host holds the remote (D10).
  bool get _transportLocked => (_sync?.transportLock ?? false) && !(_sync?.isHost ?? false);

  /// Why the transport can't be used right now, or null when it can.
  /// `indeterminate` deliberately reads as usable: before presence syncs we
  /// don't know who's here, and blocking on a guess makes entry feel broken.
  String? get _transportBlockedReason {
    if (_transportLocked) return 'The host has the remote.';
    if (_gateState != GateState.closed) return null;
    if (!_canonicalMedia.isSet) {
      return (_sync?.isHost ?? false)
          ? 'Pick something to watch first.'
          : 'Waiting for the host to pick something to watch.';
    }
    final blocker = _sync?.gateBlocker;
    final what = _canonicalMedia.name ?? 'the video';
    if (blocker == null) return 'Waiting for everyone to be ready.';
    if (blocker.userId == _sync?.userId) return 'Load $what to join in.';
    return 'Waiting for ${blocker.displayName} to load $what.';
  }

  /// Host only. D9: whether the member may come back is chosen per kick, not
  /// once as a room setting.
  Future<void> _confirmKick(PresentMember member) async {
    final allowRejoin = await showGlassDialog<bool>(
      context: context,
      width: 420,
      builder: (_) => KickMemberDialog(displayName: member.displayName),
    );
    if (allowRejoin == null || !mounted) return;
    try {
      await RoomService.instance.kickMember(
        roomId: widget.roomId,
        userId: member.userId,
        allowRejoin: allowRejoin,
      );
      // Deleting the row doesn't eject them: Realtime authorizes at subscribe
      // time, so an already-connected client keeps receiving until it
      // resubscribes. The broadcast is what actually removes them.
      await _sync?.broadcastMemberKicked(member.userId);
      if (mounted) {
        _snack('Removed ${member.displayName} from the room.', kind: .success);
      }
    } catch (e) {
      if (mounted) _snack(RoomErrorCode.fromError(e).message);
    }
  }

  bool get _selfBlocksGate {
    final sync = _sync;
    if (sync == null) return false;
    final self = _present.where((m) => m.userId == sync.userId).firstOrNull;
    return self != null && !sync.memberSatisfiesGate(self);
  }

  /// Plain-language "who are we waiting on, and for what".
  String get _gateHeadline {
    final sync = _sync;
    if (!_canonicalMedia.isSet) {
      return (sync?.isHost ?? false)
          ? 'Pick something for everyone to watch.'
          : 'Waiting for the host to pick something to watch.';
    }
    final what = _canonicalMedia.name ?? 'the video';
    final blockers = sync?.gateBlockers ?? const <PresentMember>[];
    if (blockers.isEmpty) return 'Getting everyone back in sync…';

    final others = blockers.where((m) => m.userId != sync?.userId).toList();
    if (others.isEmpty) {
      return _canonicalMedia.kind == .local ? 'Load $what to join in.' : 'Getting $what ready…';
    }
    // The wrong-file case only reads well for a single person; past that,
    // "waiting for X and Y to load <name>" covers both situations.
    if (others.length == 1 && _canonicalMedia.kind == .local && others.first.isReady) {
      final wrong = others.first.loadedFileName ?? 'nothing';
      return 'Waiting for ${others.first.displayName} to pick the right file — '
          'they currently have $wrong.';
    }
    return 'Waiting for ${_joinNames(others.map((m) => m.displayName).toList())} to load $what.';
  }

  String _joinNames(List<String> names) => switch (names.length) {
    0 => 'everyone',
    1 => names.first,
    2 => '${names[0]} and ${names[1]}',
    _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };

  /// True when the action was blocked. Every user-initiated transport action
  /// funnels through here — the dimmed widgets are affordance only, and
  /// keyboard shortcuts and double-tap skip zones never touch them.
  bool _blockTransport() {
    final reason = _transportBlockedReason;
    if (reason == null) return false;
    // Informational, not a failure: the gate or the lock is doing its job.
    _snack(reason, kind: .info);
    return true;
  }

  void _playPause() {
    if (_blockTransport()) return;
    _showControls();
    if (_mode == .youtube) {
      final controller = _youtubeController;
      if (controller == null || !_ytReady) return;
      final currentPosition = controller.value.position;
      // Toggle on intent, not iframe state — the iframe lags behind commands.
      if (_ytIntendedPlaying) {
        _ytIntendedPlaying = false;
        controller.pause();
        _sync?.broadcastPause();
      } else {
        _ytIntendedPlaying = true;
        controller.play();
        _sync?.broadcastPlay();
      }
      _sync?.broadcastSeek(currentPosition, reason: SyncActionReason.transport);
    } else {
      final currentPosition = widget.player.state.position;
      widget.player.playOrPause();
      _playing ? _sync?.broadcastPause() : _sync?.broadcastPlay();
      _sync?.broadcastSeek(currentPosition, reason: SyncActionReason.transport);
    }
  }

  /// Returns false when the gate or transport lock refused the seek, so
  /// callers can skip their own feedback (the ±10 s badge) too.
  bool _seek(Duration position) {
    if (_blockTransport()) return false;
    _showControls();
    final clamped = position < Duration.zero
        ? Duration.zero
        : (_duration != Duration.zero && position > _duration ? _duration : position);
    if (_mode == .youtube) {
      if (!_ytReady) return false;
      _ytSeekKeepingPlayState(clamped);
    } else {
      widget.player.seek(clamped);
    }
    _sync?.broadcastSeek(clamped);
    return true;
  }

  bool _skip(Duration delta) => _seek(_position + delta);

  void _flashSkip(int direction) {
    setState(() => _skipFlash = direction);
    _skipFlashTimer?.cancel();
    _skipFlashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _skipFlash = 0);
    });
  }

  Future<void> _toggleFullscreen() async {
    if (!isDesktop) return;
    await windowManager.setFullScreen(!await windowManager.isFullScreen());
  }

  Future<void> _exitFullscreen() async {
    if (!isDesktop) return;
    await windowManager.setFullScreen(false);
  }

  void _setVolume(double v) {
    if (_mode == .youtube) {
      _youtubeController?.setVolume((v * 100).round());
      setState(() => _volume = v);
    } else {
      widget.player.setVolume(v * 100);
    }
    _showControls();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      _setVolume(0);
    } else {
      _setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1.0);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // A focused text field (chat input) owns the keyboard — space must type a
    // space, not toggle playback. Esc hands focus back to player shortcuts.
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext?.findAncestorStateOfType<EditableTextState>() != null) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _shortcutFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    var handled = true;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        _playPause();
      case LogicalKeyboardKey.arrowLeft:
        _skip(const Duration(seconds: -5));
      case LogicalKeyboardKey.arrowRight:
        _skip(const Duration(seconds: 5));
      case LogicalKeyboardKey.keyJ:
        _skip(const Duration(seconds: -10));
      case LogicalKeyboardKey.keyL:
        _skip(const Duration(seconds: 10));
      case LogicalKeyboardKey.arrowUp:
        _setVolume((_volume + 0.1).clamp(0, 1));
      case LogicalKeyboardKey.arrowDown:
        _setVolume((_volume - 0.1).clamp(0, 1));
      case LogicalKeyboardKey.keyM:
        _toggleMute();
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
      case LogicalKeyboardKey.escape:
        // Ordered: text-field unfocus (handled above) → chat close →
        // fullscreen exit → let Esc bubble.
        if (_chatOpen) {
          _toggleChat();
        } else if (_fullscreen) {
          _exitFullscreen();
        } else {
          handled = false;
        }
      default:
        handled = false;
    }
    if (!handled) return KeyEventResult.ignored;
    _showControls();
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------------------
  // Controls auto-hide (overlay layouts)
  // ---------------------------------------------------------------------------

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_playing || _pointerOverControls || !_controlsVisible) {
        return;
      }
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControlsVisible() {
    // Tapping the video also steals focus from the chat input, so keyboard
    // shortcuts work again immediately.
    _shortcutFocus.requestFocus();
    if (_controlsVisible) {
      _controlsHideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _onPlayingChangedForControls(bool playing) {
    if (playing) {
      _scheduleControlsHide();
    } else {
      // Paused: controls stay up — hiding them on a paused frame helps no one.
      _controlsHideTimer?.cancel();
      if (!_controlsVisible) setState(() => _controlsVisible = true);
    }
  }

  /// Fades the floating chrome; a pointer resting on it suspends auto-hide,
  /// and any press on it restarts the countdown (touch scrubs).
  ///
  /// [fromTop] chrome drifts up as it goes and bottom chrome drifts down, so
  /// the controls *retreat* off their edge rather than dissolving in place.
  Widget _overlayControls(Widget child, {bool fromTop = false}) {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedSlide(
        // Fractions of the child's own height, so the tall control bar and the
        // thin top row travel a comparable number of pixels.
        offset: _controlsVisible ? Offset.zero : Offset(0, fromTop ? -0.3 : 0.12),
        duration: PTMotion.functional(context, PTMotion.state),
        curve: _controlsVisible ? PTMotion.enter : PTMotion.exit,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: PTMotion.functional(context, Durations.medium2),
          child: MouseRegion(
            opaque: false,
            onEnter: (_) => _pointerOverControls = true,
            onExit: (_) {
              _pointerOverControls = false;
              _scheduleControlsHide();
            },
            child: Listener(onPointerDown: (_) => _showControls(), child: child),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Expiry & eviction
  // ---------------------------------------------------------------------------

  void _tickCountdown() {
    final room = _room;
    if (room == null || _ended) return;
    final left = room.expiresAt.difference(RoomService.instance.serverNow);
    setState(() => _timeLeft = left.isNegative ? Duration.zero : left);
    if (left <= Duration.zero) {
      if (_sync?.isHost ?? false) {
        _sync?.broadcastRoomEnded();
      }
      _onRoomEnded();
    }
  }

  Future<void> _onRoomEnded() => _evictSelf();

  /// The host removed us. Same teardown as a room ending — only the copy
  /// differs — because from this client's side the room is equally over.
  Future<void> _onKicked() => _evictSelf(
    title: 'Removed from the room',
    body: 'The host removed you from this room. No hard feelings!',
    icon: Symbols.person_remove_rounded,
  );

  Future<void> _evictSelf({String? title, String? body, IconData? icon}) async {
    if (_ended) return;
    _ended = true;
    // Null closes the overflow menu if it happens to be open — otherwise it
    // sits over the "That's a wrap!" dialog listing a room that no longer runs.
    _publishMenuData();
    _countdownTimer?.cancel();
    _remotePause();
    // Unpublish mic/cam right away — not when the user finally taps
    // "Back to lobby".
    final av = _av;
    if (mounted) {
      setState(() => _av = null);
    } else {
      _av = null;
    }
    av?.dispose();
    await _sync?.disconnect();
    await widget.player.stop();
    if (mounted) _showEndedDialog(title: title, body: body, icon: icon);
  }

  void _showEndedDialog({String? title, String? body, IconData? icon}) {
    _ended = true;
    if (!mounted) return;
    final isMobile = layoutOf(context) == .portrait;
    showGlassDialog(
      context: context,
      barrierDismissible: false,
      width: isMobile ? 370 : 390,
      // canPop false: Esc/back would otherwise strand the user on a dead room
      // screen with no way to re-show this dialog.
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Column(
          mainAxisSize: .min,
          children: [
            // A slow glow behind the mark, so the room ending reads as
            // deliberate rather than as something that just stopped.
            Stack(
              alignment: .center,
              children: [
                PTPulse(
                  period: const Duration(seconds: 2),
                  low: 0.18,
                  high: 0.28,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: const BoxDecoration(color: PTColors.primary, shape: .circle),
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: PTColors.primary.withValues(alpha: 0.18),
                    shape: .circle,
                    border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.4)),
                  ),
                  child: Icon(
                    icon ?? Symbols.bedtime_rounded,
                    size: 32,
                    fill: 1,
                    color: PTColors.textAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            PTEntrance(
              delay: const Duration(milliseconds: 60),
              duration: PTMotion.state,
              offset: 8,
              child: Text(
                title ?? "That's a wrap!",
                style: PTText.screenTitle.copyWith(fontSize: 21),
              ),
            ),
            const SizedBox(height: 10),
            PTEntrance(
              delay: const Duration(milliseconds: 100),
              duration: PTMotion.state,
              offset: 8,
              child: Text(
                body ?? 'This room has ended. Head back to the lobby to start another one.',
                textAlign: .center,
                style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.5),
              ),
            ),
            const SizedBox(height: 24),
            PTEntrance(
              delay: const Duration(milliseconds: 140),
              duration: PTMotion.state,
              offset: 8,
              child: PTButton(
                label: 'Back to lobby',
                icon: Symbols.home_rounded,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  context.go('/lobby');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveRoom() async {
    try {
      await RoomService.instance.leaveRoom(widget.roomId);
    } catch (e, s) {
      // Leave for the lobby regardless — trapping someone in a room they asked
      // to leave is worse. But the membership is now stranded: it holds a slot
      // against the 8-member cap and stays eligible for host succession.
      reportNonFatal(e, s, during: 'leaving room ${widget.roomId}');
    }
    // Safe here (unlike dispose): this path always lands on the lobby, never
    // straight into another room.
    await widget.player.stop();
    if (mounted) context.go('/lobby');
  }

  Future<void> _endRoomForEveryone() async {
    try {
      await RoomService.instance.endRoom(widget.roomId);
      await _sync?.broadcastRoomEnded();
      await _onRoomEnded();
    } catch (e) {
      _snack(RoomErrorCode.fromError(e).message);
    }
  }

  // ---------------------------------------------------------------------------
  // Misc UI actions
  // ---------------------------------------------------------------------------

  /// Lifted clear of whatever owns the bottom edge in each layout: the floating
  /// control bar on desktop/landscape, the chat input in portrait. A toast that
  /// lands on the transport controls hides the thing the message is about.
  void _snack(String message, {PTSnackKind kind = PTSnackKind.error}) {
    if (!mounted) return;
    showPTSnack(
      context,
      message,
      kind: kind,
      bottomInset: switch (layoutOf(context)) {
        .desktop => 180,
        .landscape => 120,
        .portrait => 70,
      },
    );
  }

  void _copyCode() {
    final room = _room;
    if (room == null) return;
    Clipboard.setData(ClipboardData(text: room.code));
    _snack('Room code copied.', kind: .success);
  }

  void _copyInvite() {
    final room = _room;
    if (room == null) return;
    Clipboard.setData(ClipboardData(text: room.inviteLink));
    _snack('Invite link copied — send it to your people.', kind: .success);
  }

  void _openChat() {
    if (!_chatOpen) _toggleChat();
  }

  void _toggleChat() {
    setState(() {
      _chatOpen = !_chatOpen;
      if (_chatOpen) {
        _unread = 0;
        _cancelOverlayChatTimers();
      }
    });
    if (_chatOpen) {
      _chatAnim.forward();
    } else {
      _chatAnim.reverse();
    }
    // Closing chat may leave a disposed TextField as primary focus; reclaim it
    // so playback shortcuts work again.
    if (!_chatOpen) _shortcutFocus.requestFocus();
  }

  Future<void> _sendChat(String text) async {
    final message = await _sync?.sendChat(text);
    if (message != null && mounted) setState(() => _messages.add(message));
  }

  Future<void> _reloadChatHistory() async {
    try {
      final history = await _sync?.loadChatHistory();
      if (history == null || !mounted) return;
      setState(() => _mergeChatHistory(history));
    } catch (e, s) {
      // Broadcasts don't replay, so this reload is the only way messages sent
      // while we were disconnected ever arrive — losing it leaves a permanent
      // hole in the transcript.
      reportNonFatal(e, s, during: 'reloading chat history after a reconnect');
    }
  }

  /// History rows carry DB timestamps while live broadcasts carry sender-clock
  /// timestamps, so exact keys don't exist — fuzzy-match to dedupe.
  void _mergeChatHistory(List<ChatMessage> history) {
    bool same(ChatMessage a, ChatMessage b) =>
        a.senderId == b.senderId &&
        a.content == b.content &&
        a.sentAt.difference(b.sentAt).abs() <= const Duration(seconds: 10);
    for (final h in history) {
      if (!_messages.any((m) => same(m, h))) _messages.add(h);
    }
    _messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }

  void _openOverflowMenu() {
    // A null snapshot means "close" — opening on it would strand an empty panel.
    if (_ended) return;
    _publishMenuData();
    showRoomOverflowMenu(
      context: context,
      data: _menuData,
      onCopyInvite: _copyInvite,
      onLeave: _leaveRoom,
      onEndRoom: _endRoomForEveryone,
      onTransportLockChanged: _setTransportLock,
      onKick: (member) {
        final present = _present.where((p) => p.userId == member.userId).firstOrNull;
        _confirmKick(
          present ??
              PresentMember(
                userId: member.userId,
                displayName: member.displayName,
                role: member.role,
                joinedAt: member.joinedAt,
                avatarUrl: member.profile?.avatarUrl,
              ),
        );
      },
    );
  }

  Future<void> _setTransportLock(bool locked) async {
    try {
      final room = await RoomService.instance.setTransportLock(
        roomId: widget.roomId,
        locked: locked,
      );
      if (!mounted) return;
      setState(() => _room = room);
      await _sync?.broadcastTransportLock(room.transportLock);
      if (mounted) {
        _snack(
          locked ? 'You have the remote now.' : 'Everyone can use the controls again.',
          kind: .info,
        );
      }
    } catch (e) {
      if (mounted) _snack(RoomErrorCode.fromError(e).message);
    }
  }

  Future<void> _showTrackChooser({required bool subtitles}) async {
    final tracks = widget.player.state.tracks;
    final values = subtitles ? tracks.subtitle : tracks.audio;
    if (values.isEmpty) {
      _snack(
        subtitles ? 'No subtitle tracks in this video.' : 'No audio tracks in this video.',
        kind: .info,
      );
      return;
    }
    await showGlassDialog(
      context: context,
      width: 380,
      builder: (dialogContext) => subtitles
          ? ChooserDialog<SubtitleTrack>(
              type: 'Subtitles',
              values: values as List<SubtitleTrack>,
              selected: widget.player.state.track.subtitle,
              onChosen: (track) async {
                await widget.player.setSubtitleTrack(track);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
            )
          : ChooserDialog<AudioTrack>(
              type: 'Audio',
              values: values as List<AudioTrack>,
              selected: widget.player.state.track.audio,
              onChosen: (track) async {
                await widget.player.setAudioTrack(track);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
            ),
    );
  }

  String get _countdownLabel {
    final h = _timeLeft.inHours;
    final m = _timeLeft.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _timeLeft.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s left' : '$m:$s left';
  }

  String get _endsAtLabel {
    final room = _room;
    if (room == null) return '';
    final local = room.expiresAt.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $ampm';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  RoomControlBarActions get _controlActions => RoomControlBarActions(
    onPlayPause: _playPause,
    onSeek: _seek,
    onSkip: _skip,
    onMicToggle: (v) => _av?.setMicEnabled(v),
    onCamToggle: (v) => _av?.setCamEnabled(v),
    onAudioTracks: _mode == .local ? () => _showTrackChooser(subtitles: false) : null,
    onSubtitles: _mode == .local ? () => _showTrackChooser(subtitles: true) : null,
    // D1: only the host chooses what the room watches. Members keep a picker
    // purely to locate their own copy of the canonical file.
    onSwitchSource: (_sync?.isHost ?? false) ? _handleSwitchSource : null,
    onOpenFile: _mode == .local ? _pickVideo : null,
    openFileTooltip: (_sync?.isHost ?? false)
        ? 'Open file'
        : 'Locate your copy of ${_canonicalMedia.name ?? 'the file'}',
    onVolume: _setVolume,
    onToggleMute: _toggleMute,
  );

  @override
  Widget build(BuildContext context) {
    // The room sits on top of the lobby, so a system back gesture would pop
    // straight out of it — and a bare pop skips leave_room, stranding the
    // membership (member cap, authority election). Route it through _leaveRoom.
    // PopScope stays outside the loading branch so a back gesture during the
    // initial fetch is handled too.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveRoom();
      },
      child: Scaffold(
        backgroundColor: PTColors.screenBg,
        // Cross-faded so the room *resolves* out of the spinner instead of the
        // whole layout flashing into place under it.
        body: AnimatedSwitcher(
          duration: PTMotion.functional(context, PTMotion.panel),
          switchInCurve: PTMotion.enter,
          switchOutCurve: PTMotion.exit,
          child: _loading
              ? const Center(
                  key: ValueKey('loading'),
                  child: CircularProgressIndicator(color: PTColors.primary),
                )
              : Focus(
                  key: const ValueKey('room'),
                  focusNode: _shortcutFocus,
                  autofocus: true,
                  onKeyEvent: _handleKeyEvent,
                  child: PTResponsive(
                    desktop: (_) => _desktop(),
                    portrait: (_) => _portrait(),
                    landscape: (_) => _landscape(),
                  ),
                ),
        ),
      ),
    );
  }

  /// Wraps the video for touch layouts: double-tapping the left/right third
  /// skips ∓10 s (broadcast via [_skip]) with a label flash; a middle
  /// double-tap is ignored. `onTap` still toggles the chrome — accepting the
  /// ~300 ms single-tap delay the double-tap recognizer imposes (touch only).
  Widget _skipZones({required Widget child, VoidCallback? onTap}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        TapDownDetails? down;
        return GestureDetector(
          behavior: .opaque,
          onTap: onTap,
          onDoubleTapDown: (d) => down = d,
          onDoubleTap: () {
            final dx = down?.localPosition.dx ?? width / 2;
            if (dx < width / 3) {
              if (_skip(const Duration(seconds: -10))) _flashSkip(-1);
            } else if (dx > width * 2 / 3) {
              if (_skip(const Duration(seconds: 10))) _flashSkip(1);
            }
          },
          child: child,
        );
      },
    );
  }

  Widget _video() {
    return Stack(
      fit: .expand,
      children: [
        if (_mode == .local)
          Video(
            controller: controller,
            controls: NoVideoControls,
            subtitleViewConfiguration: const SubtitleViewConfiguration(padding: EdgeInsets.all(32)),
          ),
        if (_mode == .youtube && _youtubeController != null)
          // The embed is a display surface, not a control surface. Its own
          // chrome is stripped, so the only things left to click are the big
          // play button — which would bypass the readiness gate and the
          // transport lock, since those are enforced in _playPause/_seek — and
          // "Watch on YouTube", which navigates the embed away entirely. It
          // also stops the platform view from competing for the mouse cursor.
          IgnorePointer(
            child: Center(
              child: yt.YoutubePlayer(
                // Keyed on the controller, not the URL: the player never rebinds
                // its controller, so a replaced one must force a fresh element
                // rather than leave the webview driving the disposed instance.
                key: ObjectKey(_youtubeController!),
                controller: _youtubeController!,
                showVideoProgressIndicator: false,
                bottomActions: const [],
                topActions: const [],
              ),
            ),
          ),
        // Bottom scrim so glass controls always sit on something dark.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 1.1),
              radius: 1.2,
              colors: [Color(0x8C0A0812), Color(0x000A0812)],
              stops: [0.0, 0.55],
            ),
          ),
        ),
        // Cross-faded rather than mounted/unmounted: this covers every buffer
        // stall, not just room entry, and popping a scrim over the video on
        // each one is the flickeriest thing in the room.
        AnimatedOpacity(
          opacity: _showBuffering || _awaitingFirstSource ? 1 : 0,
          duration: PTMotion.functional(context, PTMotion.panel),
          // Opacity 0 skips painting but does NOT stop tickers, and this slot
          // now stays mounted for the whole session so it can fade. Without
          // TickerMode the spinner would drive a repaint every frame of every
          // film, forever.
          child: TickerMode(
            enabled: _showBuffering || _awaitingFirstSource,
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0x59000000),
                child: Center(
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      const SizedBox.square(
                        dimension: 44,
                        child: CircularProgressIndicator(color: PTColors.primary, strokeWidth: 3),
                      ),
                      if (_awaitingFirstSource) ...[
                        const SizedBox(height: 18),
                        Text('Setting up the room…', style: PTText.caption),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Covers the video only — chat, facecams and the member list stay
        // interactive while the room waits (D2). Mounted for as long as the
        // reveal is non-zero rather than while the gate is shut, so the exit
        // animation gets to play — and so the roster's entrance stagger fires
        // when the overlay actually appears, not when the room screen builds.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _gateCurve,
            builder: (context, _) {
              final t = _gateCurve.value;
              // IgnorePointer even when empty: Positioned.fill hands down tight
              // constraints, so a bare SizedBox still fills (and blocks) the slot.
              if (t == 0) return const IgnorePointer(child: SizedBox.shrink());
              return IgnorePointer(
                ignoring: _gateAnim.status == AnimationStatus.reverse,
                child: ReadinessOverlay(
                  reveal: t,
                  headline: _gateHeadline,
                  members: _present,
                  media: _canonicalMedia,
                  selfId: _sync?.userId ?? '',
                  selfIsHost: _sync?.isHost ?? false,
                  compact: MediaQuery.sizeOf(context).width < 700,
                  onLocateFile: _selfBlocksGate && _canonicalMedia.kind == .local
                      ? _pickVideo
                      : null,
                  onKick: _confirmKick,
                ),
              );
            },
          ),
        ),
        if (_skipFlash != 0)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: _skipFlash < 0 ? const Alignment(-0.55, 0) : const Alignment(0.55, 0),
                child: _skipFlashBadge(_skipFlash < 0),
              ),
            ),
          ),
        Positioned(
          top: 72,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              // Drops in from above and rises on the way out. The pill is glass,
              // so fading it does flatten the blur for the duration — accepted
              // here because `Opacity` skips painting entirely at zero, which
              // keeps a dormant BackdropFilter off the playing video.
              child: AnimatedSlide(
                offset: _actionToastVisible ? Offset.zero : const Offset(0, -0.4),
                duration: PTMotion.functional(context, PTMotion.state),
                curve: !_actionToastVisible
                    ? PTMotion.exit
                    : _actionToastArrival
                    ? PTMotion.arrive
                    : PTMotion.enter,
                child: AnimatedOpacity(
                  opacity: _actionToastVisible ? 1 : 0,
                  duration: PTMotion.functional(context, PTMotion.state),
                  child: GlassPill(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Row(
                      mainAxisSize: .min,
                      spacing: 8,
                      children: [
                        const Icon(Symbols.sync_alt_rounded, size: 16, color: PTColors.textAccent),
                        // A second action landing while the toast is still up
                        // swaps the line rather than hard-cutting it.
                        AnimatedSize(
                          duration: PTMotion.functional(context, PTMotion.state),
                          curve: PTMotion.enter,
                          child: AnimatedSwitcher(
                            duration: PTMotion.functional(context, PTMotion.state),
                            switchInCurve: PTMotion.enter,
                            switchOutCurve: PTMotion.exit,
                            child: Text(
                              _actionToastText,
                              key: ValueKey(_actionToastText),
                              style: PTText.body.copyWith(
                                fontSize: 13,
                                color: PTColors.white(0.85),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _skipFlashBadge(bool backward) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(_skipFlashTimer),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.linear,
      // Grows into place over the first quarter, then fades for the rest, so
      // the ±10 s stamp lands with some weight instead of just appearing.
      builder: (_, t, child) => Opacity(
        opacity: 1 - Curves.easeIn.transform(t),
        child: Transform.scale(
          scale: 0.85 + 0.15 * PTMotion.enter.transform((t * 4).clamp(0.0, 1.0)),
          child: child,
        ),
      ),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.42), shape: .circle),
        child: Column(
          mainAxisAlignment: .center,
          spacing: 2,
          children: [
            Icon(
              backward ? Symbols.replay_10_rounded : Symbols.forward_10_rounded,
              size: 32,
              color: Colors.white,
            ),
            Text('10s', style: PTText.mono.copyWith(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _roomPill({bool compact = false}) {
    final room = _room!;
    return GlassPill(
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18, vertical: compact ? 8 : 10),
      child: Row(
        mainAxisSize: .min,
        spacing: compact ? 12 : 16,
        children: [
          Flexible(
            child: Text(
              room.name,
              overflow: .ellipsis,
              style: PTText.panelHeading.copyWith(fontSize: compact ? 13 : 15),
            ),
          ),
          RoomCodeChip(code: room.code, onCopy: _copyCode, fontSize: compact ? 11 : 13),
          // Urgency without layout movement — this sits right next to the
          // video, so nothing here may reflow or jitter.
          Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              PTPulse(
                enabled: _timeLeft > Duration.zero && _timeLeft <= const Duration(minutes: 1),
                low: 0.35,
                child: Icon(
                  Symbols.schedule_rounded,
                  size: compact ? 13 : 16,
                  color: PTColors.white(0.7),
                ),
              ),
              AnimatedDefaultTextStyle(
                duration: PTMotion.functional(context, PTMotion.state),
                curve: PTMotion.enter,
                style: PTText.mono.copyWith(
                  fontSize: compact ? 11 : 13,
                  color: _timeLeft > Duration.zero && _timeLeft <= const Duration(minutes: 5)
                      ? PTColors.warning
                      : PTColors.white(0.7),
                ),
                child: Text(_countdownLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Banners, each sliding down into place instead of popping.
  ///
  /// The stable `ValueKey`s live on the *wrapper*, not the `PTBanner`: they are
  /// what stops `_tickCountdown`'s per-second rebuild from restarting the T-5
  /// auto-dismiss ring, and an unkeyed wrapper would reintroduce that by making
  /// the list match children positionally again.
  List<Widget> _banners() {
    return [
      if (!_warningDismissed &&
          _timeLeft > Duration.zero &&
          _timeLeft <= const Duration(minutes: 5))
        PTEntrance(
          key: const ValueKey('t5-warning'),
          offset: -8,
          duration: PTMotion.state,
          child: PTBanner(
            autoDismissAfter: const Duration(seconds: 10),
            pulseOnArrival: true,
            kind: .warning,
            icon: Symbols.timer_rounded,
            title: () {
              final mins = (_timeLeft.inSeconds / 60).ceil();
              return '$mins minute${mins == 1 ? '' : 's'} left';
            }(),
            subtitle: 'Time to wrap up — this room ends at $_endsAtLabel.',
            onDismiss: () => setState(() => _warningDismissed = true),
          ),
        ),
      if (!_connected)
        const PTEntrance(
          key: ValueKey('reconnecting'),
          offset: -8,
          duration: PTMotion.state,
          child: PTBanner(
            kind: .info,
            icon: Symbols.sync_rounded,
            spinIcon: true,
            title: 'Reconnecting…',
            subtitle: 'Hang tight, getting you back in sync.',
          ),
        ),
      if (_durationDrifts)
        PTEntrance(
          key: const ValueKey('duration-drift'),
          offset: -8,
          duration: PTMotion.state,
          child: PTBanner(
            kind: .warning,
            icon: Symbols.difference_rounded,
            title: 'Same name, different length',
            subtitle:
                'Your copy of ${_roomFile!.name} runs a little different — you might drift apart.',
            trailing: PTButton(
              label: 'Pick another',
              variant: .secondary,
              height: 38,
              expand: false,
              onPressed: _pickVideo,
            ),
            onDismiss: () => setState(() => _mismatchDismissed = true),
          ),
        ),
    ];
  }

  /// Collapses to nothing when the last banner goes, so dismissing one doesn't
  /// yank the layout by a banner height.
  Widget _bannerStack({required double spacing, EdgeInsets padding = EdgeInsets.zero}) {
    final banners = _banners();
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      alignment: .topCenter,
      child: banners.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: padding,
              child: Column(spacing: spacing, children: banners),
            ),
    );
  }

  /// Floating stack of the last few incoming messages, shown while the chat
  /// panel is closed (desktop/landscape). Bottom-aligned so new bubbles push up.
  /// Deliberately *not* wrapped in an `IgnorePointer`: the bubbles themselves are
  /// tap targets that open the panel, and the bare Column/Padding around them
  /// hit-tests children only, so the empty gaps still pass clicks to the video.
  Widget _chatOverlay() {
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      alignment: .bottomLeft,
      child: Column(
        mainAxisSize: .min,
        mainAxisAlignment: .end,
        crossAxisAlignment: .start,
        children: [
          for (final message in _overlayChat)
            Padding(
              // Identity lives here, on the Column's direct child, so the
              // animation wrappers below can't shuffle State between bubbles.
              key: ValueKey(message),
              padding: const EdgeInsets.only(top: 8),
              child: AnimatedSlide(
                offset: _expiringChat.contains(message) ? const Offset(-0.12, 0) : Offset.zero,
                duration: PTMotion.functional(context, PTMotion.state),
                curve: PTMotion.exit,
                child: AnimatedOpacity(
                  opacity: _expiringChat.contains(message) ? 0 : 1,
                  duration: PTMotion.functional(context, PTMotion.state),
                  child: PTEntrance(
                    duration: PTMotion.panel,
                    offset: 8,
                    child: _overlayBubble(message),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _overlayBubble(ChatMessage message) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        // Opaque so the bubble's padding is tappable too, not just its text —
        // the Row hugs its content, so this claims no space beyond the bubble.
        behavior: .opaque,
        onTap: _openChat,
        child: _overlayBubbleBody(message),
      ),
    );
  }

  Widget _overlayBubbleBody(ChatMessage message) {
    return Row(
      mainAxisSize: .min,
      crossAxisAlignment: .end,
      spacing: 8,
      children: [
        PTAvatar(userId: message.senderId, displayName: message.displayName, size: 26),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF141022).withValues(alpha: 0.74),
              border: Border.all(color: PTColors.white(0.1)),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomRight: Radius.circular(14),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(
                  message.displayName,
                  style: const TextStyle(
                    fontFamily: PTFonts.body,
                    fontSize: 11,
                    fontWeight: .w600,
                    color: PTColors.textAccent,
                  ),
                ),
                Text(message.content, style: PTText.body.copyWith(fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The chat panel itself: slides in from off the right edge (the Stack clips
  /// it on the way past) and unmounts at rest, so the panel and its autofocused
  /// input only exist while it's on screen. Deliberately *not* faded — the
  /// panel is a GlassPanel, and an Opacity layer around a BackdropFilter leaves
  /// it sampling an empty layer, i.e. the glass goes flat mid-animation.
  Widget _chatRevealed({required double offscreen, required Widget panel}) {
    return AnimatedBuilder(
      animation: _chatCurve,
      child: panel,
      builder: (_, child) {
        final t = _chatCurve.value;
        // IgnorePointer even when empty: the Positioned parent hands down tight
        // constraints, so a bare SizedBox still fills (and blocks) the slot.
        if (t == 0) return const IgnorePointer(child: SizedBox.shrink());
        return IgnorePointer(
          ignoring: _chatAnim.status == AnimationStatus.reverse,
          child: Transform.translate(offset: Offset((1 - t) * offscreen, 0), child: child),
        );
      },
    );
  }

  /// Chrome the open panel takes the place of (facecam rail, floating
  /// bubbles): cross-fades out against the panel's arrival instead of popping.
  Widget _chatDisplaced(Widget displaced) {
    return AnimatedBuilder(
      animation: _chatCurve,
      child: displaced,
      builder: (_, child) {
        final t = _chatCurve.value;
        if (t == 1) return const SizedBox.shrink();
        return IgnorePointer(
          ignoring: t > 0,
          child: Opacity(opacity: (1 - t).clamp(0.0, 1.0), child: child),
        );
      },
    );
  }

  Widget _chatToggleButton() {
    return UnreadBadge(
      count: _unread,
      child: PTIconButton(
        icon: Symbols.chat_bubble_rounded,
        active: _chatOpen,
        tooltip: _chatOpen ? 'Close chat' : 'Party chat',
        onPressed: _toggleChat,
      ),
    );
  }

  Widget _desktop() {
    return MouseRegion(
      // Any mouse motion revives the chrome, like every desktop video player.
      onHover: (_) => _showControls(),
      cursor: _controlsVisible ? MouseCursor.defer : SystemMouseCursors.none,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: .opaque,
              onTap: _toggleControlsVisible,
              child: _video(),
            ),
          ),
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            // Expanded (not Flexible+Spacer: they'd split the free space 50/50,
            // stranding the action icons mid-screen) pins the icons to the edge.
            child: _overlayControls(
              fromTop: true,
              Row(
                crossAxisAlignment: .start,
                children: [
                  Expanded(
                    child: Align(alignment: .topLeft, child: _roomPill()),
                  ),
                  const SizedBox(width: 16),
                  _chatToggleButton(),
                  const SizedBox(width: 12),
                  PTIconButton(
                    icon: Symbols.more_vert_rounded,
                    iconSize: 22,
                    onPressed: _openOverflowMenu,
                  ),
                ],
              ),
            ),
          ),
          AnimatedPositioned(
            duration: _chatMotion,
            curve: _chatOpen ? Curves.easeOutCubic : Curves.easeInCubic,
            top: 90,
            left: 240,
            right: _chatOpen ? 378 : 240,
            child: _bannerStack(spacing: 12),
          ),
          if (_av != null && _camsVisible)
            Positioned(
              top: 84,
              left: 24,
              child: FacecamRail(
                av: _av!,
                present: _present,
                selfId: _sync?.userId ?? '',
                layout: .railLeft,
                onHide: () => setState(() => _camsVisible = false),
              ),
            ),
          if (_av != null && !_camsVisible)
            Positioned(
              top: 84,
              left: 24,
              child: PTActionPill(
                label: 'Show cams',
                icon: Symbols.keyboard_arrow_right_rounded,
                onTap: () => setState(() => _camsVisible = true),
              ),
            ),
          if (_sync != null)
            Positioned(
              top: 84,
              right: 24,
              bottom: 178,
              width: 330,
              child: _chatRevealed(
                // Panel width + its right margin: starts fully off the edge.
                offscreen: 354,
                panel: RoomChatPanel(
                  sync: _sync!,
                  messages: _messages,
                  typingNames: _typingNames,
                  watchingCount: _present.length,
                  onClose: _toggleChat,
                  onSend: _sendChat,
                  autofocus: true,
                ),
              ),
            ),
          if (_overlayChat.isNotEmpty)
            Positioned(left: 24, bottom: 170, width: 340, child: _chatDisplaced(_chatOverlay())),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: _overlayControls(
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: RoomControlBar(
                    playing: _playing,
                    position: _position,
                    duration: _duration,
                    volume: _volume,
                    micOn: _av?.micEnabled ?? false,
                    camOn: _av?.camEnabled ?? false,
                    avAvailable: _av != null,
                    actions: _controlActions,
                    transportEnabled: _transportBlockedReason == null,
                    transportHint: _transportBlockedReason,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _portrait() {
    final room = _room!;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 3,
                    children: [
                      Text(
                        room.name,
                        overflow: .ellipsis,
                        style: PTText.panelHeading.copyWith(fontSize: 16),
                      ),
                      Row(
                        spacing: 8,
                        children: [
                          RoomCodeChip(code: room.code, onCopy: _copyCode, fontSize: 11),
                          Icon(Symbols.schedule_rounded, size: 13, color: PTColors.white(0.6)),
                          Text(
                            _countdownLabel,
                            style: PTText.mono.copyWith(fontSize: 11, color: PTColors.white(0.6)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PTIconButton(
                  icon: Symbols.more_vert_rounded,
                  iconSize: 22,
                  onPressed: _openOverflowMenu,
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _skipZones(child: _video()),
          ),
          if (_av != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: FacecamRail(
                av: _av!,
                present: _present,
                selfId: _sync?.userId ?? '',
                layout: .stripTop,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: RoomControlBar(
              playing: _playing,
              position: _position,
              duration: _duration,
              volume: _volume,
              micOn: _av?.micEnabled ?? false,
              camOn: _av?.camEnabled ?? false,
              avAvailable: _av != null,
              actions: _controlActions,
              transportEnabled: _transportBlockedReason == null,
              transportHint: _transportBlockedReason,
              compact: true,
            ),
          ),
          _bannerStack(spacing: 10, padding: const EdgeInsets.fromLTRB(14, 10, 14, 0)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141022).withValues(alpha: 0.5),
                    border: Border(
                      top: BorderSide(color: PTColors.white(0.1)),
                      left: BorderSide(color: PTColors.white(0.1)),
                      right: BorderSide(color: PTColors.white(0.1)),
                    ),
                  ),
                  child: _sync != null
                      ? RoomChatPanel(
                          sync: _sync!,
                          messages: _messages,
                          typingNames: _typingNames,
                          watchingCount: _present.length,
                          onClose: () {},
                          onSend: _sendChat,
                          embedded: true,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _landscape() {
    return Stack(
      children: [
        Positioned.fill(
          child: _skipZones(onTap: _toggleControlsVisible, child: _video()),
        ),
        SafeArea(
          minimum: const EdgeInsets.symmetric(horizontal: 56),
          child: Stack(
            children: [
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: _overlayControls(
                  fromTop: true,
                  Row(
                    crossAxisAlignment: .start,
                    children: [
                      Expanded(
                        child: Align(alignment: .topLeft, child: _roomPill(compact: true)),
                      ),
                      const SizedBox(width: 12),
                      _chatToggleButton(),
                      const SizedBox(width: 10),
                      PTIconButton(
                        icon: Symbols.more_vert_rounded,
                        iconSize: 21,
                        onPressed: _openOverflowMenu,
                      ),
                    ],
                  ),
                ),
              ),
              if (_av != null)
                Positioned(
                  top: 72,
                  right: 0,
                  child: SizedBox(
                    width: 104,
                    child: _chatDisplaced(
                      FacecamRail(
                        av: _av!,
                        present: _present,
                        selfId: _sync?.userId ?? '',
                        layout: .miniStackRight,
                        maxTiles: 3,
                      ),
                    ),
                  ),
                ),
              if (_sync != null)
                Positioned(
                  top: 72,
                  right: 0,
                  bottom: 86,
                  width: 300,
                  child: _chatRevealed(
                    offscreen: 300,
                    panel: RoomChatPanel(
                      sync: _sync!,
                      messages: _messages,
                      typingNames: _typingNames,
                      watchingCount: _present.length,
                      onClose: _toggleChat,
                      onSend: _sendChat,
                    ),
                  ),
                ),
              Positioned(top: 66, left: 0, width: 340, child: _bannerStack(spacing: 8)),
              if (_overlayChat.isNotEmpty)
                Positioned(left: 0, bottom: 96, width: 300, child: _chatDisplaced(_chatOverlay())),
              Positioned(
                bottom: 22,
                left: 0,
                right: 0,
                child: _overlayControls(
                  RoomControlBar(
                    playing: _playing,
                    position: _position,
                    duration: _duration,
                    volume: _volume,
                    micOn: _av?.micEnabled ?? false,
                    camOn: _av?.camEnabled ?? false,
                    avAvailable: _av != null,
                    actions: _controlActions,
                    transportEnabled: _transportBlockedReason == null,
                    transportHint: _transportBlockedReason,
                    compact: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
