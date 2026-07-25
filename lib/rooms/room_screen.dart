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
import 'package:playtogether/platform.dart';
import 'package:playtogether/player/chooser_dialog.dart';
import 'package:playtogether/player/mode_selection_dialog.dart';
import 'package:playtogether/player/youtube_url_dialog.dart';
import 'package:playtogether/profile/profile_service.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/rooms/room_service.dart';
import 'package:playtogether/rooms/widgets/facecam_rail.dart';
import 'package:playtogether/rooms/widgets/room_chat_panel.dart';
import 'package:playtogether/rooms/widgets/room_control_bar.dart';
import 'package:playtogether/rooms/widgets/room_overflow_menu.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:playtogether/ui/banners.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/identity.dart';
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

class _RoomScreenState extends State<RoomScreen>
    with WindowListener, SingleTickerProviderStateMixin {
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
  Timer? _actionToastTimer;

  // Floating chat bubbles (last 3) shown over the video while the panel is
  // closed (desktop/landscape only — portrait chat is always visible). Each
  // self-expires; timers are tracked so they can be cancelled on dispose, and
  // on open (where the bubbles instead fade out under the arriving panel).
  final _overlayChat = <ChatMessage>[];
  final _overlayChatTimers = <Timer>{};

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

  ({String name, Duration duration})? _roomFile;
  String? _localFileName;
  bool _mismatchDismissed = false;

  final _subscriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    if (isDesktop) windowManager.addListener(this);
    // Bubbles are kept alive (fading) until the panel has fully covered them.
    _chatAnim.addStatusListener((status) {
      if (status == AnimationStatus.completed && _overlayChat.isNotEmpty) {
        setState(_overlayChat.clear);
      }
    });
    _init();
  }

  @override
  void onWindowEnterFullScreen() => setState(() => _fullscreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullscreen = false);

  Future<void> _init() async {
    final profile =
        ProfileService.instance.profile ?? await ProfileService.instance.load();
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
    } catch (_) {
      loadFailed = true;
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
    } catch (_) {
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
      sync.fileInfoStream.listen(_onRemoteFileInfo),
      sync.roomEndedStream.listen((_) => _onRoomEnded()),
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
        if (_mode == .local) setState(() => _duration = duration);
      }),
      widget.player.stream.buffering.listen((buffering) {
        if (_mode == .local) setState(() => _buffering = buffering);
      }),
      widget.player.stream.volume.listen((volume) => setState(() => _volume = volume / 100)),
    ]);

    setState(() {
      _room = room;
      _sync = sync;
      _loading = false;
    });

    await sync.connect();
    unawaited(_reloadChatHistory());

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
    _tickCountdown();

    // If the state-sync window closes with no media, we're first in — ask
    // what to watch.
    _idleSourceTimer = Timer(const Duration(milliseconds: 4500), () {
      if (!mounted) return;
      setState(() => _awaitingFirstSource = false);
      if (_ended) return;
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
    for (final t in _overlayChatTimers) {
      t.cancel();
    }
    _shortcutFocus.dispose();
    _chatCurve.dispose();
    _chatAnim.dispose();
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
    // Membership can change under us (join/leave/host succession).
    try {
      final members = await RoomService.instance.fetchMembers(widget.roomId);
      if (!mounted) return;
      setState(() => _members = members);
      final selfRole =
          members.where((m) => m.userId == _sync?.userId).firstOrNull?.role;
      if (selfRole != null) _sync?.updateRole(selfRole);
    } catch (_) {}
  }

  Set<String> get _onlineIds => _present.map((m) => m.userId).toSet();

  void _onRemoteAction(RemoteAction action) {
    final name = _present.where((m) => m.userId == action.senderId).firstOrNull?.displayName ??
        _members.where((m) => m.userId == action.senderId).firstOrNull?.displayName ??
        'Someone';
    final text = switch (action.kind) {
      RemoteActionKind.seek => '$name jumped to ${_clock(action.position ?? Duration.zero)}',
      RemoteActionKind.play => '$name hit play',
      RemoteActionKind.pause => '$name paused',
    };
    setState(() {
      _actionToastText = text;
      _actionToastVisible = true;
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
      if (_overlayChat.length > 3) _overlayChat.removeAt(0);
    });
    late final Timer timer;
    timer = Timer(const Duration(seconds: 5), () {
      _overlayChatTimers.remove(timer);
      if (mounted) setState(() => _overlayChat.remove(message));
    });
    _overlayChatTimers.add(timer);
  }

  void _cancelOverlayChatTimers() {
    for (final t in _overlayChatTimers) {
      t.cancel();
    }
    _overlayChatTimers.clear();
  }

  // ---------------------------------------------------------------------------
  // Remote playback routing (dual player)
  // ---------------------------------------------------------------------------

  bool get _ytReady => _youtubeController?.value.isReady ?? false;

  /// Spinner shows only while the player is stalled AND meant to be playing —
  /// a buffer that fills behind a paused frame needs no indicator. YouTube's
  /// state reads `buffering` (not `playing`) mid-stall, so gate it on intent.
  bool get _showBuffering =>
      _buffering && (_mode == .youtube ? _ytIntendedPlaying : _playing);

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
      if (_awaitingFirstSource) setState(() => _awaitingFirstSource = false);
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
    if (_awaitingFirstSource) setState(() => _awaitingFirstSource = false);
    final mode = await showGlassDialog<InitialMode>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ModeSelectionDialog(),
    );
    _isModeSelectionDialogOpen = false;
    if (!mounted) return;

    if (mode == InitialMode.local) {
      await _pickVideo();
    } else if (mode == InitialMode.youtube) {
      _isYouTubeUrlDialogOpen = true;
      _urlDialogDismissedRemotely = false;
      final url = await showGlassDialog<String>(
        context: context,
        width: 440,
        builder: (_) => const YouTubeUrlDialog(),
      );
      _isYouTubeUrlDialogOpen = false;
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
    setState(() {
      _mode = .youtube;
      _youtubeUrl = url;
      _roomFile = null;
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
  }

  Future<void> _switchToLocalMode() async {
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
    await _pickVideo();
  }

  void _onYouTubePlayerEvent() {
    final controller = _youtubeController;
    if (controller == null) return;

    _flushPendingYtCommands(controller);

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
        _sync?.broadcastSeek(controller.value.position);
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
      }
    } else {
      await _switchToLocalMode();
      _sync?.broadcastModeSwitch('local', null);
    }
  }

  Future<void> _handleSwitchSource() async {
    if (_mode == .local) {
      _isYouTubeUrlDialogOpen = true;
      final url = await showGlassDialog<String>(
        context: context,
        width: 440,
        builder: (_) => const YouTubeUrlDialog(),
      );
      _isYouTubeUrlDialogOpen = false;
      if (url != null && mounted) await _handleModeSwitch(.youtube, url);
    } else {
      await _handleModeSwitch(.local, null);
    }
  }

  Future<void> _pickVideo() async {
    const videoTypeGroup = XTypeGroup(label: 'Videos', extensions: ['mp4', 'mkv']);
    final response = await FastFilePicker.pickFile(acceptedTypeGroups: [videoTypeGroup]);
    final uri = response?.uri ?? response?.path;
    if (uri == null) return;
    await widget.player.open(Media(uri), play: false);
    final name = uri.split(RegExp(r'[/\\]')).last;
    _localFileName = name;
    _mismatchDismissed = false;
    // Duration arrives async after open.
    unawaited(
      widget.player.stream.duration
          .firstWhere((d) => d != Duration.zero)
          .timeout(const Duration(seconds: 10))
          .then((duration) => _sync?.broadcastFileInfo(name, duration))
          .catchError((_) => null),
    );
    setState(() {});
  }

  void _onRemoteFileInfo(dynamic event) {
    setState(() {
      _roomFile = (
        name: event.fileName as String,
        duration: Duration(milliseconds: event.durationMs as int),
      );
      _mismatchDismissed = false;
    });
  }

  bool get _fileMismatch {
    final roomFile = _roomFile;
    if (_mode != .local || roomFile == null || _mismatchDismissed) return false;
    if (_localFileName == null) return true; // room is watching, we have nothing
    if (_localFileName != roomFile.name) return true;
    if (_duration != Duration.zero &&
        roomFile.duration != Duration.zero &&
        (_duration - roomFile.duration).abs() > const Duration(seconds: 2)) {
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // User playback actions (act locally + broadcast; play/pause also seek)
  // ---------------------------------------------------------------------------

  void _playPause() {
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
      _sync?.broadcastSeek(currentPosition);
    } else {
      final currentPosition = widget.player.state.position;
      widget.player.playOrPause();
      _playing ? _sync?.broadcastPause() : _sync?.broadcastPlay();
      _sync?.broadcastSeek(currentPosition);
    }
  }

  void _seek(Duration position) {
    _showControls();
    final clamped = position < Duration.zero
        ? Duration.zero
        : (_duration != Duration.zero && position > _duration ? _duration : position);
    if (_mode == .youtube) {
      if (!_ytReady) return;
      _ytSeekKeepingPlayState(clamped);
    } else {
      widget.player.seek(clamped);
    }
    _sync?.broadcastSeek(clamped);
  }

  void _skip(Duration delta) => _seek(_position + delta);

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
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;

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
      if (!mounted || !_playing || _pointerOverControls || !_controlsVisible) return;
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
  Widget _overlayControls(Widget child) {
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: Durations.medium2,
        child: MouseRegion(
          opaque: false,
          onEnter: (_) => _pointerOverControls = true,
          onExit: (_) {
            _pointerOverControls = false;
            _scheduleControlsHide();
          },
          child: Listener(
            onPointerDown: (_) => _showControls(),
            child: child,
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

  Future<void> _onRoomEnded() async {
    if (_ended) return;
    _ended = true;
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
    if (mounted) _showEndedDialog();
  }

  void _showEndedDialog() {
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
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: PTColors.primary.withValues(alpha: 0.18),
              shape: .circle,
              border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.4)),
            ),
            child: const Icon(Symbols.bedtime_rounded, size: 32, fill: 1, color: PTColors.textAccent),
          ),
          const SizedBox(height: 18),
          Text("That's a wrap!", style: PTText.screenTitle.copyWith(fontSize: 21)),
          const SizedBox(height: 10),
          Text(
            'This room has ended. Head back to the lobby to start another one.',
            textAlign: .center,
            style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.5),
          ),
          const SizedBox(height: 24),
          PTButton(
            label: 'Back to lobby',
            icon: Symbols.home_rounded,
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.go('/lobby');
            },
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _leaveRoom() async {
    try {
      await RoomService.instance.leaveRoom(widget.roomId);
    } catch (_) {}
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _copyCode() {
    final room = _room;
    if (room == null) return;
    Clipboard.setData(ClipboardData(text: room.code));
    _snack('Room code copied.');
  }

  void _copyInvite() {
    final room = _room;
    if (room == null) return;
    Clipboard.setData(ClipboardData(text: room.inviteLink));
    _snack('Invite link copied — send it to your people.');
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
    } catch (_) {}
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
    showRoomOverflowMenu(
      context: context,
      members: _members,
      onlineIds: _onlineIds,
      selfId: _sync?.userId ?? '',
      selfIsHost: _sync?.isHost ?? false,
      onCopyInvite: _copyInvite,
      onLeave: _leaveRoom,
      onEndRoom: _endRoomForEveryone,
    );
  }

  Future<void> _showTrackChooser({required bool subtitles}) async {
    final tracks = widget.player.state.tracks;
    final values = subtitles ? tracks.subtitle : tracks.audio;
    if (values.isEmpty) {
      _snack(subtitles ? 'No subtitle tracks in this video.' : 'No audio tracks in this video.');
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
    onSwitchSource: _handleSwitchSource,
    onOpenFile: _mode == .local ? _pickVideo : null,
    onVolume: _setVolume,
    onToggleMute: _toggleMute,
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: PTColors.primary)),
      );
    }
    return Scaffold(
      backgroundColor: PTColors.screenBg,
      body: Focus(
        focusNode: _shortcutFocus,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: PTResponsive(
          desktop: (_) => _desktop(),
          portrait: (_) => _portrait(),
          landscape: (_) => _landscape(),
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
              _skip(const Duration(seconds: -10));
              _flashSkip(-1);
            } else if (dx > width * 2 / 3) {
              _skip(const Duration(seconds: 10));
              _flashSkip(1);
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
            subtitleViewConfiguration: const SubtitleViewConfiguration(
              padding: EdgeInsets.all(32),
            ),
          ),
        if (_mode == .youtube && _youtubeController != null)
          Center(
            child: yt.YoutubePlayer(
              key: ValueKey(_youtubeUrl),
              controller: _youtubeController!,
              showVideoProgressIndicator: false,
              bottomActions: const [],
              topActions: const [],
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
        if (_showBuffering || _awaitingFirstSource)
          ColoredBox(
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
              child: AnimatedOpacity(
                opacity: _actionToastVisible ? 1 : 0,
                duration: Durations.short4,
                child: GlassPill(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Row(
                    mainAxisSize: .min,
                    spacing: 8,
                    children: [
                      const Icon(Symbols.sync_alt_rounded, size: 16, color: PTColors.textAccent),
                      Text(
                        _actionToastText,
                        style: PTText.body.copyWith(fontSize: 13, color: PTColors.white(0.85)),
                      ),
                    ],
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
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeIn,
      builder: (_, t, child) => Opacity(opacity: t, child: child),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          shape: .circle,
        ),
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
          Row(
            mainAxisSize: .min,
            spacing: 6,
            children: [
              Icon(Symbols.schedule_rounded, size: compact ? 13 : 16, color: PTColors.white(0.7)),
              Text(
                _countdownLabel,
                style: PTText.mono.copyWith(fontSize: compact ? 11 : 13, color: PTColors.white(0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _banners() {
    return [
      if (!_warningDismissed && _timeLeft > Duration.zero && _timeLeft <= const Duration(minutes: 5))
        PTBanner(
          kind: .warning,
          icon: Symbols.timer_rounded,
          title: () {
            final mins = (_timeLeft.inSeconds / 60).ceil();
            return '$mins minute${mins == 1 ? '' : 's'} left';
          }(),
          subtitle: 'Time to wrap up — this room ends at $_endsAtLabel.',
          onDismiss: () => setState(() => _warningDismissed = true),
        ),
      if (!_connected)
        const PTBanner(
          kind: .info,
          icon: Symbols.sync_rounded,
          title: 'Reconnecting…',
          subtitle: 'Hang tight, getting you back in sync.',
        ),
      if (_fileMismatch)
        PTBanner(
          kind: .error,
          icon: Symbols.difference_rounded,
          title: 'Different file loaded',
          subtitle:
              'The room is watching ${_roomFile!.name} — your file doesn\'t match.',
          trailing: PTButton(
            label: 'Pick file',
            variant: .secondary,
            height: 38,
            expand: false,
            onPressed: _pickVideo,
          ),
          onDismiss: () => setState(() => _mismatchDismissed = true),
        ),
    ];
  }

  /// Floating stack of the last few incoming messages, shown while the chat
  /// panel is closed (desktop/landscape). Bottom-aligned so new bubbles push up.
  Widget _chatOverlay() {
    return IgnorePointer(
      child: Column(
        mainAxisSize: .min,
        mainAxisAlignment: .end,
        crossAxisAlignment: .start,
        children: [
          for (final message in _overlayChat)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(message),
                tween: Tween(begin: 0, end: 1),
                duration: Durations.medium2,
                curve: Curves.easeOut,
                builder: (_, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
                ),
                child: _overlayBubble(message),
              ),
            ),
        ],
      ),
    );
  }

  Widget _overlayBubble(ChatMessage message) {
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
          child: Transform.translate(
            offset: Offset((1 - t) * offscreen, 0),
            child: child,
          ),
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
            Row(
              crossAxisAlignment: .start,
              children: [
                Expanded(child: Align(alignment: .topLeft, child: _roomPill())),
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
          child: Column(
            spacing: 12,
            children: _banners(),
          ),
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
          Positioned(
            left: 24,
            bottom: 170,
            width: 340,
            child: _chatDisplaced(_chatOverlay()),
          ),
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
          AspectRatio(aspectRatio: 16 / 9, child: _skipZones(child: _video())),
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
              compact: true,
            ),
          ),
          for (final banner in _banners())
            Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), child: banner),
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
                  Row(
                    crossAxisAlignment: .start,
                    children: [
                      Expanded(child: Align(alignment: .topLeft, child: _roomPill(compact: true))),
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
              Positioned(
                top: 66,
                left: 0,
                width: 340,
                child: Column(spacing: 8, children: _banners()),
              ),
              if (_overlayChat.isNotEmpty)
                Positioned(
                  left: 0,
                  bottom: 96,
                  width: 300,
                  child: _chatDisplaced(_chatOverlay()),
                ),
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
