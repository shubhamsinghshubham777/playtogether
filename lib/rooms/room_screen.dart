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
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as yt;

enum PlaybackMode { local, youtube }

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.roomId, required this.player});

  final String roomId;
  final Player player;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
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
  bool _isModeSelectionDialogOpen = false;
  bool _isYouTubeUrlDialogOpen = false;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;

  final _messages = <ChatMessage>[];
  List<String> _typingNames = const [];
  bool _chatOpen = false;
  int _unread = 0;
  bool _camsVisible = true;

  Timer? _countdownTimer;
  Duration _timeLeft = Duration.zero;
  bool _warningDismissed = false;
  bool _connected = true;
  bool _ended = false;
  Timer? _idleSourceTimer;

  ({String name, Duration duration})? _roomFile;
  String? _localFileName;
  bool _mismatchDismissed = false;

  final _subscriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final profile =
        ProfileService.instance.profile ?? await ProfileService.instance.load();
    if (profile == null) {
      if (mounted) context.go('/login');
      return;
    }

    Room? room;
    try {
      room = await RoomService.instance.fetchRoom(widget.roomId);
      await RoomService.instance.syncServerTime();
    } catch (_) {
      room = null;
    }
    if (!mounted) return;
    if (room == null ||
        room.endedAt != null ||
        room.expiresAt.isBefore(RoomService.instance.serverNow)) {
      _showEndedDialog();
      return;
    }

    _members = await RoomService.instance.fetchMembers(widget.roomId);
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
      }),
      sync.typingStream.listen((names) => setState(() => _typingNames = names)),
      sync.presenceStream.listen(_onPresenceChanged),
      sync.modeSwitchStream.listen(_onRemoteModeSwitch),
      sync.fileInfoStream.listen(_onRemoteFileInfo),
      sync.roomEndedStream.listen((_) => _onRoomEnded()),
      sync.connectionStream.listen((up) => setState(() => _connected = up)),
      widget.player.stream.playing.listen((playing) {
        if (_mode == .local) setState(() => _playing = playing);
      }),
      widget.player.stream.position.listen((position) {
        if (_mode == .local) setState(() => _position = position);
      }),
      widget.player.stream.duration.listen((duration) {
        if (_mode == .local) setState(() => _duration = duration);
      }),
      widget.player.stream.volume.listen((volume) => setState(() => _volume = volume / 100)),
    ]);

    setState(() {
      _room = room;
      _sync = sync;
      _loading = false;
    });

    await sync.connect();
    sync.loadChatHistory().then((history) {
      if (!mounted) return;
      setState(() => _messages.insertAll(0, history));
    }).catchError((_) {});

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
    _tickCountdown();

    // If the state-sync window closes with no media, we're first in — ask
    // what to watch.
    _idleSourceTimer = Timer(const Duration(milliseconds: 4500), () {
      if (!mounted || _ended) return;
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
    for (final s in _subscriptions) {
      s.cancel();
    }
    _countdownTimer?.cancel();
    _idleSourceTimer?.cancel();
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

  // ---------------------------------------------------------------------------
  // Remote playback routing (dual player)
  // ---------------------------------------------------------------------------

  void _remotePlay() {
    if (_mode == .youtube) {
      _youtubeController?.play();
    } else {
      widget.player.play();
    }
  }

  void _remotePause() {
    if (_mode == .youtube) {
      _youtubeController?.pause();
    } else {
      widget.player.pause();
    }
  }

  void _remoteSeek(Duration position) {
    if (_mode == .youtube) {
      _youtubeController?.seekTo(position);
      _youtubeController?.pause(); // prevent auto-play after seek
    } else {
      widget.player.seek(position);
    }
  }

  void _remoteDriftCorrect(Duration position) {
    if (_mode == .youtube) {
      _youtubeController?.seekTo(position); // no pause: playback continues
    } else {
      widget.player.seek(position);
    }
  }

  // ---------------------------------------------------------------------------
  // Mode switching (ported from PTVideoPlayer — dialog dismissal is delicate)
  // ---------------------------------------------------------------------------

  Future<void> _onRemoteModeSwitch(dynamic event) async {
    if (mounted) {
      // URL dialog sits on top of the source chooser; pop in that order.
      if (_isYouTubeUrlDialogOpen) {
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
      final url = await showGlassDialog<String>(
        context: context,
        width: 440,
        builder: (_) => const YouTubeUrlDialog(),
      );
      _isYouTubeUrlDialogOpen = false;
      if (!mounted) return;
      if (url != null) {
        await _handleModeSwitch(.youtube, url);
      } else if (_mode == .local && widget.player.state.duration == Duration.zero) {
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
      _position = Duration.zero;
      _duration = Duration.zero;

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
      _youtubeController?.dispose();
      _youtubeController = null;
      _playing = widget.player.state.playing;
      _position = widget.player.state.position;
      _duration = widget.player.state.duration;
    });
    _sync?.updatePlaybackState('local', null);
    await _pickVideo();
  }

  void _onYouTubePlayerEvent() {
    final controller = _youtubeController;
    if (controller == null) return;

    final state = controller.value.playerState;
    final isPlaying = state == .playing;

    setState(() {
      _playing = isPlaying;
      _position = controller.value.position;
      final meta = controller.metadata.duration;
      if (meta != Duration.zero) _duration = meta;
    });

    if (isPlaying && !_youtubeWasPlaying) {
      _youtubeWasPlaying = true;
      _sync?.broadcastPlay();
    } else if (!isPlaying && _youtubeWasPlaying && state == .paused) {
      _youtubeWasPlaying = false;
      _sync?.broadcastPause();
    }

    if (controller.value.hasError) {
      _snack('Failed to load that YouTube video.');
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
    if (_mode == .youtube) {
      final controller = _youtubeController;
      if (controller == null) return;
      final currentPosition = controller.value.position;
      if (controller.value.playerState == .playing) {
        controller.pause();
        _sync?.broadcastPause();
      } else {
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
    final clamped = position < Duration.zero
        ? Duration.zero
        : (_duration != Duration.zero && position > _duration ? _duration : position);
    if (_mode == .youtube) {
      _youtubeController?.seekTo(clamped);
    } else {
      widget.player.seek(clamped);
    }
    _sync?.broadcastSeek(clamped);
  }

  void _skip(Duration delta) => _seek(_position + delta);

  void _setVolume(double v) {
    if (_mode == .youtube) {
      _youtubeController?.setVolume((v * 100).round());
      setState(() => _volume = v);
    } else {
      widget.player.setVolume(v * 100);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        _playPause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _skip(const Duration(seconds: -5));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _skip(const Duration(seconds: 5));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyJ:
        _skip(const Duration(seconds: -10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        _skip(const Duration(seconds: 10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _setVolume((_volume + 0.1).clamp(0, 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _setVolume((_volume - 0.1).clamp(0, 1));
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
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
      builder: (dialogContext) => Column(
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
      if (_chatOpen) _unread = 0;
    });
  }

  Future<void> _sendChat(String text) async {
    final message = await _sync?.sendChat(text);
    if (message != null) setState(() => _messages.add(message));
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
      ],
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
          title: '${_timeLeft.inMinutes + 1} minutes left',
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
    return Stack(
      children: [
        Positioned.fill(child: _video()),
        Positioned(
          top: 24,
          left: 24,
          right: 24,
          child: Row(
            crossAxisAlignment: .start,
            children: [
              Flexible(child: _roomPill()),
              const Spacer(),
              Row(
                spacing: 12,
                children: [
                  _chatToggleButton(),
                  PTIconButton(
                    icon: Symbols.more_vert_rounded,
                    iconSize: 22,
                    onPressed: _openOverflowMenu,
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
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
        if (_chatOpen && _sync != null)
          Positioned(
            top: 84,
            right: 24,
            bottom: 178,
            width: 330,
            child: RoomChatPanel(
              sync: _sync!,
              messages: _messages,
              typingNames: _typingNames,
              watchingCount: _present.length,
              onClose: _toggleChat,
              onSend: _sendChat,
            ),
          ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
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
      ],
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
          AspectRatio(aspectRatio: 16 / 9, child: _video()),
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
        Positioned.fill(child: _video()),
        SafeArea(
          minimum: const EdgeInsets.symmetric(horizontal: 56),
          child: Stack(
            children: [
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Row(
                  crossAxisAlignment: .start,
                  children: [
                    Flexible(child: _roomPill(compact: true)),
                    const Spacer(),
                    Row(
                      spacing: 10,
                      children: [
                        _chatToggleButton(),
                        PTIconButton(
                          icon: Symbols.more_vert_rounded,
                          iconSize: 21,
                          onPressed: _openOverflowMenu,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_av != null && !_chatOpen)
                Positioned(
                  top: 72,
                  right: 0,
                  child: SizedBox(
                    width: 104,
                    child: FacecamRail(
                      av: _av!,
                      present: _present,
                      selfId: _sync?.userId ?? '',
                      layout: .miniStackRight,
                      maxTiles: 3,
                    ),
                  ),
                ),
              if (_chatOpen && _sync != null)
                Positioned(
                  top: 72,
                  right: 0,
                  bottom: 86,
                  width: 300,
                  child: RoomChatPanel(
                    sync: _sync!,
                    messages: _messages,
                    typingNames: _typingNames,
                    watchingCount: _present.length,
                    onClose: _toggleChat,
                    onSend: _sendChat,
                  ),
                ),
              Positioned(
                top: 66,
                left: 0,
                width: 340,
                child: Column(spacing: 8, children: _banners()),
              ),
              Positioned(
                bottom: 22,
                left: 0,
                right: 0,
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
            ],
          ),
        ),
      ],
    );
  }
}
