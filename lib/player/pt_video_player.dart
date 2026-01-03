import 'dart:async';

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:playtogether/chat/chat_box.dart';
import 'package:playtogether/player/chooser_dialog.dart';
import 'package:playtogether/player/mode_selection_dialog.dart';
import 'package:playtogether/player/progress_section.dart';
import 'package:playtogether/player/youtube_controls.dart';
import 'package:playtogether/player/youtube_url_dialog.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as yt;

enum PlaybackMode { local, youtube }

class PTVideoPlayer extends StatefulWidget {
  const PTVideoPlayer(this.player, this.syncService, {super.key});

  final Player player;
  final SyncService syncService;

  @override
  State<PTVideoPlayer> createState() => _PTVideoPlayerState();
}

class _PTVideoPlayerState extends State<PTVideoPlayer> {
  late final controller = VideoController(widget.player);

  bool _isChatOpen = false;
  int _unreadCount = 0;
  bool _isPeerOnline = false;
  StreamSubscription? _chatSubscription;
  StreamSubscription? _presenceSubscription;

  // YouTube mode state
  PlaybackMode _currentMode = .local;
  String? _currentYoutubeUrl;
  yt.YoutubePlayerController? _youtubeController;
  StreamSubscription? _modeSwitchSubscription;
  bool _youtubeWasPlaying = false;
  bool _isModeSelectionDialogOpen = false;
  bool _isYouTubeUrlDialogOpen = false;

  @override
  void initState() {
    super.initState();

    // Show mode selection dialog on startup
    WidgetsBinding.instance.addPostFrameCallback((_) => _showModeSelectionDialog());

    _isPeerOnline = widget.syncService.isPeerOnline;
    _chatSubscription = widget.syncService.chatMessages.listen((_) {
      if (!_isChatOpen) {
        setState(() => _unreadCount++);
      }
    });
    _presenceSubscription = widget.syncService.peerOnlineStream.listen((isOnline) {
      setState(() => _isPeerOnline = isOnline);
    });

    // Subscribe to mode switch events
    _modeSwitchSubscription = widget.syncService.modeSwitchStream.listen((event) async {
      // Close all open dialogs when receiving a remote mode switch
      if (mounted) {
        // If YouTube URL dialog is open, close it first (it's on top)
        if (_isYouTubeUrlDialogOpen) {
          Navigator.of(context).pop();
          _isYouTubeUrlDialogOpen = false;
        }
        // Then close mode selection dialog if it's open (it's underneath)
        if (_isModeSelectionDialogOpen) {
          Navigator.of(context).pop();
          _isModeSelectionDialogOpen = false;
        }
      }

      final PlaybackMode mode = event.mode == 'youtube' ? .youtube : .local;
      if (mode == .youtube && event.youtubeUrl != null) {
        _switchToYouTubeMode(event.youtubeUrl!);
      } else {
        await _switchToLocalMode();
      }
    });

    // Set up remote control callbacks
    widget.syncService.onRemotePlay = () {
      if (_currentMode == .youtube) {
        _youtubeController?.play();
      } else {
        widget.player.play();
      }
    };

    widget.syncService.onRemotePause = () {
      if (_currentMode == .youtube) {
        _youtubeController?.pause();
      } else {
        widget.player.pause();
      }
    };

    widget.syncService.onRemoteSeek = (position) {
      if (_currentMode == PlaybackMode.youtube) {
        _youtubeController?.seekTo(position);
        _youtubeController?.pause(); // Prevent auto-play after seek
      } else {
        widget.player.seek(position);
      }
    };
  }

  Future<void> _showModeSelectionDialog() async {
    _isModeSelectionDialogOpen = true;
    final mode = await showDialog<InitialMode>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ModeSelectionDialog(),
    );
    _isModeSelectionDialogOpen = false;

    if (!mounted) return;

    if (mode == InitialMode.local) {
      await pickVideo();
      // No need to broadcast, already in local mode by default
    } else if (mode == InitialMode.youtube) {
      _isYouTubeUrlDialogOpen = true;
      final url = await showDialog<String>(context: context, builder: (_) => YouTubeUrlDialog());
      _isYouTubeUrlDialogOpen = false;
      if (!mounted) return;

      if (url != null) {
        await _handleModeSwitch(.youtube, url);
      } else if (_currentMode == .local) {
        // User cancelled and mode hasn't been remotely switched, show dialog again
        _showModeSelectionDialog();
      }
      // If mode is already youtube, a remote mode switch occurred, don't re-show dialog
    }
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _presenceSubscription?.cancel();
    _modeSwitchSubscription?.cancel();
    _youtubeController?.dispose();
    super.dispose();
  }

  void _toggleChat() {
    setState(() {
      _isChatOpen = !_isChatOpen;
      if (_isChatOpen) _unreadCount = 0;
    });
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

  Future<void> _switchToYouTubeMode(String url) async {
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid YouTube URL')));
      }
      return;
    }

    setState(() {
      _currentMode = .youtube;
      _currentYoutubeUrl = url;

      // Dispose old YouTube controller if exists
      _youtubeController?.dispose();

      // Create new YouTube controller
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

      // Listen to YouTube player state changes for sync
      _youtubeController!.addListener(_onYouTubePlayerEvent);
    });

    // Update sync service with current state
    widget.syncService.updatePlaybackState('youtube', url);
  }

  Future<void> _switchToLocalMode() async {
    setState(() {
      _currentMode = .local;
      _currentYoutubeUrl = null;

      // Dispose YouTube controller
      _youtubeController?.dispose();
      _youtubeController = null;
    });

    // Update sync service
    widget.syncService.updatePlaybackState('local', null);

    // Automatically prompt user to select a video file
    await pickVideo();
  }

  void _onYouTubePlayerEvent() {
    if (_youtubeController == null) return;

    final state = _youtubeController!.value.playerState;
    final isPlaying = state == .playing;

    // Detect play/pause changes and broadcast
    if (isPlaying && !_youtubeWasPlaying) {
      _youtubeWasPlaying = true;
      widget.syncService.broadcastPlay();
    } else if (!isPlaying && _youtubeWasPlaying && state == .paused) {
      _youtubeWasPlaying = false;
      widget.syncService.broadcastPause();
    }

    // Handle errors
    if (_youtubeController!.value.hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load YouTube video')));
    }
  }

  Future<void> _handleModeSwitch(PlaybackMode targetMode, String? url) async {
    if (targetMode == .youtube) {
      if (url != null) {
        await _switchToYouTubeMode(url);
        widget.syncService.broadcastModeSwitch('youtube', url);
      }
    } else {
      await _switchToLocalMode();
      widget.syncService.broadcastModeSwitch('local', null);
    }
  }

  Future<void> _handleChangeYouTubeUrl() async {
    _isYouTubeUrlDialogOpen = true;
    final url = await showDialog<String>(
      context: context,
      builder: (context) => YouTubeUrlDialog(),
    );
    _isYouTubeUrlDialogOpen = false;
    if (!mounted) return;

    if (url != null) {
      await _switchToYouTubeMode(url);
      widget.syncService.broadcastModeSwitch('youtube', url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Row(
      children: [
        Expanded(
          child: Stack(
            children: [
              // Conditionally render local video player
              if (_currentMode == .local)
                Video(
                  controller: controller,
                  controls: (_) => _PTVideoPlayerControls(
                    player: widget.player,
                    syncService: widget.syncService,
                    mode: .local,
                    youtubeController: null,
                    onModeSwitch: _handleModeSwitch,
                    onSelectVideo: pickVideo,
                  ),
                  subtitleViewConfiguration: SubtitleViewConfiguration(padding: EdgeInsets.all(32)),
                ),

              // Conditionally render YouTube player
              if (_currentMode == .youtube && _youtubeController != null)
                yt.YoutubePlayer(
                  key: ValueKey(_currentYoutubeUrl),
                  controller: _youtubeController!,
                  showVideoProgressIndicator: false,
                  bottomActions: [],
                  topActions: [],
                ),

              // Overlay custom YouTube controls for YouTube mode
              if (_currentMode == .youtube && _youtubeController != null)
                YouTubeControls(
                  controller: _youtubeController!,
                  syncService: widget.syncService,
                  onSwitchToLocal: () => _handleModeSwitch(.local, null),
                  onChangeUrl: _handleChangeYouTubeUrl,
                ),

              if (_isPeerOnline)
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Online', style: TextStyle(color: Colors.white, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 16,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Badge(
                    isLabelVisible: _unreadCount > 0,
                    label: Text('$_unreadCount'),
                    child: IconButton.filled(
                      onPressed: _toggleChat,
                      icon: const Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ClipRect(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: _isChatOpen ? screenWidth * 0.35 : 0,
            constraints: BoxConstraints(maxWidth: 300),
            child: _isChatOpen
                ? PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) _toggleChat();
                    },
                    child: ChatBox(syncService: widget.syncService, onClose: _toggleChat),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Future<void> pickVideo() async {
    const XTypeGroup videoTypeGroup = XTypeGroup(label: 'Videos', extensions: ['mp4', 'mkv']);
    final response = await FastFilePicker.pickFile(acceptedTypeGroups: [videoTypeGroup]);
    final uri = response?.uri ?? response?.path;
    if (uri != null) await widget.player.open(Media(uri), play: false);
  }
}

class _PTVideoPlayerControls extends StatefulWidget {
  const _PTVideoPlayerControls({
    required this.player,
    required this.syncService,
    required this.mode,
    required this.youtubeController,
    required this.onModeSwitch,
    required this.onSelectVideo,
  });

  final Player player;
  final SyncService syncService;
  final PlaybackMode mode;
  final yt.YoutubePlayerController? youtubeController;
  final Future<void> Function(PlaybackMode mode, String? url) onModeSwitch;
  final VoidCallback onSelectVideo;

  @override
  State<_PTVideoPlayerControls> createState() => _PTVideoPlayerControlsState();
}

class _PTVideoPlayerControlsState extends State<_PTVideoPlayerControls> {
  bool showControls = true;
  final playing = ValueNotifier(false);
  final duration = ValueNotifier(Duration.zero);
  final position = ValueNotifier(Duration.zero);
  final volume = ValueNotifier(100.0);
  final audioTracks = ValueNotifier(<AudioTrack>[]);
  final subtitleTracks = ValueNotifier(<SubtitleTrack>[]);

  final _subscriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();

    final state = widget.player.state;
    playing.value = state.playing;
    duration.value = state.duration;
    position.value = state.position;
    volume.value = state.volume;

    final stream = widget.player.stream;
    _subscriptions.addAll([
      stream.playing.listen((playing) => this.playing.value = playing),
      stream.duration.listen((duration) => this.duration.value = duration),
      stream.position.listen((position) => this.position.value = position),
      stream.volume.listen((volume) => this.volume.value = volume),
      stream.tracks.listen((tracks) {
        audioTracks.value = tracks.audio;
        subtitleTracks.value = tracks.subtitle;
      }),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    playing.dispose();
    duration.dispose();
    position.dispose();
    volume.dispose();
    audioTracks.dispose();
    subtitleTracks.dispose();
    super.dispose();
  }

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final controlsWidget = AnimatedSwitcher(
      duration: Durations.short2,
      child: !showControls
          ? null
          : Align(
              alignment: .bottomCenter,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colors.surfaceContainer,
                ),
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: .min,
                  spacing: 16,
                  children: [
                    Row(
                      spacing: 24,
                      children: [
                        // Audio Tracks Button
                        Center(
                          child: ValueListenableBuilder(
                            valueListenable: audioTracks,
                            builder: (context, audioTracks, _) {
                              return IconButton(
                                onPressed: audioTracks.isEmpty
                                    ? null
                                    : () => showDialog(
                                        context: context,
                                        builder: (context) => ChooserDialog(
                                          type: 'Audio',
                                          values: audioTracks,
                                          onChosen: (track) async {
                                            await widget.player.setAudioTrack(track);
                                            if (context.mounted) Navigator.of(context).pop();
                                          },
                                        ),
                                      ),
                                icon: Icon(Icons.audiotrack_rounded),
                                iconSize: 32,
                              );
                            },
                          ),
                        ),

                        // Mode Switch Button
                        Center(
                          child: IconButton(
                            onPressed: () async {
                              if (widget.mode == .local) {
                                // Switch TO YouTube - show URL dialog
                                final url = await showDialog<String>(
                                  context: context,
                                  builder: (_) => YouTubeUrlDialog(),
                                );
                                if (url != null) await widget.onModeSwitch(.youtube, url);
                              } else {
                                // Switch TO local mode
                                await widget.onModeSwitch(.local, null);
                              }
                            },
                            icon: Icon(
                              widget.mode == .local ? Icons.play_circle_outline : Icons.video_file,
                            ),
                            iconSize: 32,
                          ),
                        ),

                        // Play/Pause Button
                        Center(
                          child: ValueListenableBuilder(
                            valueListenable: playing,
                            builder: (context, playing, _) {
                              // Determine if YouTube is playing
                              final isYoutubePlaying =
                                  widget.mode == .youtube &&
                                  widget.youtubeController?.value.playerState == .playing;
                              final isPlaying = widget.mode == .youtube
                                  ? isYoutubePlaying
                                  : playing;

                              return IconButton(
                                onPressed: () {
                                  if (widget.mode == .youtube) {
                                    final controller = widget.youtubeController;
                                    if (controller != null) {
                                      final currentPosition = controller.value.position;
                                      if (controller.value.playerState == .playing) {
                                        controller.pause();
                                        widget.syncService.broadcastPause();
                                        widget.syncService.broadcastSeek(currentPosition);
                                      } else {
                                        controller.play();
                                        widget.syncService.broadcastPlay();
                                        widget.syncService.broadcastSeek(currentPosition);
                                      }
                                    }
                                  } else {
                                    final currentPosition = widget.player.state.position;
                                    widget.player.playOrPause();
                                    if (playing) {
                                      widget.syncService.broadcastPause();
                                      widget.syncService.broadcastSeek(currentPosition);
                                    } else {
                                      widget.syncService.broadcastPlay();
                                      widget.syncService.broadcastSeek(currentPosition);
                                    }
                                  }
                                },
                                icon: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                ),
                                iconSize: 64,
                              );
                            },
                          ),
                        ),

                        // Subtitle Tracks Button
                        Center(
                          child: ValueListenableBuilder(
                            valueListenable: subtitleTracks,
                            builder: (context, subtitleTracks, _) {
                              return IconButton(
                                onPressed: subtitleTracks.isEmpty
                                    ? null
                                    : () => showDialog(
                                        context: context,
                                        builder: (context) => ChooserDialog(
                                          type: 'Subtitle',
                                          values: subtitleTracks,
                                          onChosen: (track) async {
                                            await widget.player.setSubtitleTrack(track);
                                            if (context.mounted) Navigator.of(context).pop();
                                          },
                                        ),
                                      ),
                                icon: Icon(Icons.subtitles),
                                iconSize: 32,
                              );
                            },
                          ),
                        ),

                        // Select Video Button (only in local mode)
                        if (widget.mode == .local)
                          Center(
                            child: IconButton(
                              onPressed: widget.onSelectVideo,
                              icon: Icon(Icons.folder_open),
                              iconSize: 32,
                              tooltip: 'Select video file',
                            ),
                          ),
                      ].map((child) => Expanded(child: child)).toList(),
                    ),
                    ValueListenableBuilder(
                      valueListenable: duration,
                      builder: (context, duration, _) => ValueListenableBuilder(
                        valueListenable: position,
                        builder: (context, position, _) {
                          return ProgressSection(
                            position: position,
                            duration: duration,
                            onSeek: (newPosition) async {
                              if (widget.mode == .youtube) {
                                widget.youtubeController?.seekTo(newPosition);
                              } else {
                                await widget.player.seek(newPosition);
                              }
                              widget.syncService.broadcastSeek(newPosition);
                            },
                            volumeSection: ValueListenableBuilder(
                              valueListenable: volume,
                              builder: (context, volume, _) => Row(
                                spacing: 8,
                                children: [
                                  Icon(Icons.volume_up),
                                  Container(
                                    width: 150,
                                    margin: EdgeInsets.only(right: 16),
                                    child: Slider(
                                      padding: EdgeInsets.zero,
                                      value: (volume / 100).clamp(0, 1),
                                      onChanged: (value) {
                                        widget.player.setVolume(value * 100);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _isMobile
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => showControls = !showControls),
                child: controlsWidget,
              )
            : Focus(
                autofocus: true,
                onKeyEvent: handleKeyEvent,
                child: MouseRegion(
                  onEnter: (_) => setState(() => showControls = true),
                  onExit: (_) => setState(() => showControls = false),
                  child: controlsWidget,
                ),
              ),
      ),
    );
  }

  KeyEventResult handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        final currentPosition = widget.player.state.position;
        widget.player.playOrPause();
        if (playing.value) {
          widget.syncService.broadcastPause();
          widget.syncService.broadcastSeek(currentPosition);
        } else {
          widget.syncService.broadcastPlay();
          widget.syncService.broadcastSeek(currentPosition);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        final newPos = position.value - Duration(seconds: 5);
        widget.player.seek(newPos);
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        final newPos = position.value + Duration(seconds: 5);
        widget.player.seek(newPos);
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        widget.player.setVolume(volume.value + 10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        widget.player.setVolume(volume.value - 10);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyJ:
        final newPos = position.value - Duration(seconds: 10);
        widget.player.seek(newPos);
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        final newPos = position.value + Duration(seconds: 10);
        widget.player.seek(newPos);
        widget.syncService.broadcastSeek(newPos);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }
}
