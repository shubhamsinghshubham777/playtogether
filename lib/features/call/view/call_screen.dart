import 'dart:async';
import 'dart:convert';

import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';
import 'package:playtogether/features/call/model/call_screen_state.dart';
import 'package:playtogether/features/call/view/pt_video_controls.dart';
import 'package:playtogether/features/dashboard/provider/friend_provider.dart';
import 'package:playtogether/utils.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    required this.callerUid,
    required this.calleeUid,
    required this.offer,
    super.key,
  });

  final String callerUid;
  final String calleeUid;
  final dynamic offer;

  static Future<void> deleteCallRelatedData(String calleeUid) async {
    debugPrint('Deleting doc having id: $calleeUid');

    final docToDelete =
        FirebaseFirestore.instance.collection('calls').doc(calleeUid);

    final candidatesCollectionToDelete = docToDelete.collection('candidates');

    final candidatesCollectionData = await candidatesCollectionToDelete.get();

    debugPrint('Deleting candidates...');

    await candidatesCollectionData.docs
        .map((doc) => doc.reference.delete())
        .wait;

    debugPrint('Deleting complete doc...');

    await docToDelete.delete();

    debugPrint('Call data deletion complete ✅');
  }

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with WidgetsBindingObserver {
  final _localRTCVideoRenderer = RTCVideoRenderer();
  final _remoteRTCVideoRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  RTCPeerConnection? _rtcPeerConnection;
  RTCDataChannel? _rtcDataChannel;
  List<RTCIceCandidate> rtcIceCadidates = [];
  bool isAudioOn = true;
  bool isVideoOn = true;
  bool isFrontCameraSelected = true;

  StreamSubscription<dynamic>? _candidateListener;
  StreamSubscription<dynamic>? _docExistanceListener;

  late final videoPlayer = Player();
  late final videoController = VideoController(videoPlayer);

  var screenState = const CallScreenState(
    videoName: null,
    isPlayingVideo: false,
    currentVideoMillis: 0,
    chatMessage: null,
  );

  String? localVideoName;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _localRTCVideoRenderer.initialize();
    _remoteRTCVideoRenderer.initialize();
    _setupPeerConnection().then((_) => _observeIfFirebaseDocExistsElseLeave());
    super.initState();
  }

  @override
  void setState(VoidCallback fn) {
    if (!mounted) {
      return;
    }

    super.setState(fn);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshLocalStream();
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
      _docExistanceListener?.cancel();
      _candidateListener?.cancel();
      CallScreen.deleteCallRelatedData(widget.calleeUid);
      _localRTCVideoRenderer.dispose();
      _remoteRTCVideoRenderer.dispose();
      _localStream?.dispose();
      _rtcDataChannel?.close();
      _rtcPeerConnection?.dispose();
      videoPlayer.dispose();
    } catch (e, st) {
      debugPrint('Error while disposing call screen: ${e.toString()}');
      debugPrintStack(stackTrace: st);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callerData =
        ref.watch(userProvider(uid: widget.callerUid)).valueOrNull;

    final calleeData =
        ref.watch(userProvider(uid: widget.calleeUid)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: context.pop<void>,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Room'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _openVideoPicker,
            icon: const Icon(Icons.upload),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: context.isLandscape
          ? _buildLandscapeScreen(
              callerData: callerData,
              calleeData: calleeData,
            )
          : _buildPortraitScreen(
              callerData: callerData,
              calleeData: calleeData,
            ),
    );
  }

  Column _buildLandscapeScreen({PTUser? calleeData, PTUser? callerData}) {
    final rtcVideoViewSize = context.mediaQueryShortestSide * 0.35;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildVideoPlayer()),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(
                    width: rtcVideoViewSize,
                    height: rtcVideoViewSize,
                    child: _RTCVideoView(
                      videoRenderer: _localRTCVideoRenderer,
                      mirror: false,
                      user: callerData,
                    ),
                  ),
                  SizedBox(
                    width: rtcVideoViewSize,
                    height: rtcVideoViewSize,
                    child: _RTCVideoView(
                      videoRenderer: _remoteRTCVideoRenderer,
                      mirror: false,
                      user: calleeData,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
            ],
          ),
        ),
        _buildVideoName(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPortraitScreen({PTUser? callerData, PTUser? calleeData}) {
    return Column(
      children: [
        _buildVideoPlayer(),
        _buildVideoName(),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _RTCVideoView(
                      videoRenderer: _localRTCVideoRenderer,
                      mirror: false,
                      user: callerData,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _RTCVideoView(
                      videoRenderer: _remoteRTCVideoRenderer,
                      mirror: true,
                      user: calleeData,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Padding _buildVideoName() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        callback(() {
          if (screenState.videoName == null) {
            return 'No video loaded, tap the button on the top right to add one';
          }

          if (screenState.videoName != localVideoName) {
            return 'Please load the same video as the other person!';
          }

          return screenState.videoName ?? '';
        }),
        style: context.titleLarge?.copyWith(
          color: screenState.videoName == null ||
                  screenState.videoName != localVideoName
              ? context.theme.colorScheme.error
              : null,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: context.isLandscape ? context.height : context.height / 2,
          child: Video(
            controller: videoController,
            controls: (_) => PTVideoControls(
              videoPlayer,
              onPlayPause: (isPlaying, positionMillis) {
                _controlsLog(
                  'isPlaying: $isPlaying, '
                  'positionMillis: $positionMillis',
                );
                _updateScreenState(
                  screenState.copyWith(
                    isPlayingVideo: isPlaying,
                    currentVideoMillis: positionMillis,
                  ),
                );
              },
              onSeek: (positionMillis) {
                _controlsLog('onSeek: $positionMillis');
                _updateScreenState(
                  screenState.copyWith(currentVideoMillis: positionMillis),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openVideoPicker() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      videoPlayer.open(Media(result.files.single.path!), play: false);
      final videoName = result.files.single.name;
      localVideoName = videoName;
      _updateScreenState(screenState.copyWith(videoName: videoName));
    }
  }

  Future<void> _setupPeerConnection() async {
    // create peer connection
    _rtcPeerConnection = await createPeerConnection({
      'iceServers': [
        {
          'urls': [
            'stun:stun1.l.google.com:19302',
            'stun:stun2.l.google.com:19302'
          ]
        }
      ]
    });

    // listen for remotePeer mediaTrack event
    _rtcPeerConnection?.onTrack = (event) {
      _remoteRTCVideoRenderer.srcObject = event.streams[0];
      setState(() {});
    };

    _rtcPeerConnection?.onDataChannel = (channel) {
      _rtcDataChannel = channel;
      _setupDataChannel();
    };

    // get localStream
    _localStream = await navigator.mediaDevices.getUserMedia(_mediaConstraints);

    // add mediaTrack to peerConnection
    _localStream?.getTracks().forEach((track) {
      _rtcPeerConnection?.addTrack(track, _localStream!);
    });

    // set source for local video renderer
    _localRTCVideoRenderer.srcObject = _localStream;
    setState(() {});

    // Incoming call
    if (widget.offer != null) {
      // set SDP offer as remoteDescription for peerConnection
      await _rtcPeerConnection?.setRemoteDescription(
        RTCSessionDescription(widget.offer["sdp"], widget.offer["type"]),
      );

      // create SDP answer
      final answer = await _rtcPeerConnection!.createAnswer();

      // set SDP answer as localDescription for peerConnection
      _rtcPeerConnection?.setLocalDescription(answer);

      FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.calleeUid)
          .update({'answer': answer.toMap()});

      // listen for Remote IceCandidate
      _candidateListener = FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.calleeUid)
          .collection('candidates')
          .snapshots()
          .listen((snapshot) {
        for (final doc in snapshot.docs) {
          debugPrint('Candidates doc: $doc');
          final candidate = doc.data();
          String rtcCandidate = candidate["candidate"];
          String sdpMid = candidate["id"];
          int sdpMLineIndex = candidate["label"];
          // add iceCandidate
          _rtcPeerConnection?.addCandidate(
            RTCIceCandidate(rtcCandidate, sdpMid, sdpMLineIndex),
          );
        }
        setState(() {});
      });
    }
    // Outgoing call
    else {
      // listen for local iceCandidate and add it to the list of IceCandidate
      _rtcPeerConnection?.onIceCandidate =
          (RTCIceCandidate candidate) => rtcIceCadidates.add(candidate);

      _rtcDataChannel = await _rtcPeerConnection?.createDataChannel(
        'chat',
        RTCDataChannelInit(),
      );
      _setupDataChannel();

      // Initialise the document
      FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.calleeUid)
          .set({});

      // create SDP Offer
      final offer = await _rtcPeerConnection!.createOffer();

      // set SDP offer as localDescription for peerConnection
      await _rtcPeerConnection?.setLocalDescription(offer);

      // make a call to remote peer over signalling
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.calleeUid)
          .update({'callerId': widget.callerUid, 'offer': offer.toMap()});

      debugPrint('calleeUid: ${widget.calleeUid}');
      // Observe when the callee accepts the call
      _candidateListener = FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.calleeUid)
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.data()?.containsKey('answer') ?? false) {
          final data = snapshot.data()?['answer'];
          // Callee has accepted the call
          await _rtcPeerConnection?.setRemoteDescription(
            RTCSessionDescription(data["sdp"], data["type"]),
          );

          // send iceCandidate generated to remote peer over signalling
          final candidatesCollectionRef = FirebaseFirestore.instance
              .collection('calls')
              .doc(widget.calleeUid)
              .collection('candidates');

          for (final candidate in rtcIceCadidates) {
            await candidatesCollectionRef.add({
              "id": candidate.sdpMid,
              "label": candidate.sdpMLineIndex,
              "candidate": candidate.candidate,
            });
          }
        }
      });
    }
  }

  void _setupDataChannel() {
    _rtcDataChannel?.onMessage = (message) {
      debugPrint('Received msg: ${message.text}');
      setState(() {
        screenState = CallScreenState.fromJson(jsonDecode(message.text));
      });
      videoPlayer.seek(Duration(milliseconds: screenState.currentVideoMillis));
      (screenState.isPlayingVideo ? videoPlayer.play() : videoPlayer.pause());
    };
  }

  void _observeIfFirebaseDocExistsElseLeave() {
    _docExistanceListener = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.calleeUid)
        .snapshots()
        .listen((snapshot) {
      try {
        if (!snapshot.exists && mounted) context.pop<void>();
      } catch (e, st) {
        debugPrint('Could not pop screen! Reason: $e');
        debugPrintStack(stackTrace: st);
      }
    });
  }

  Future<void> _updateScreenState(CallScreenState localState) async {
    setState(() => screenState = localState);
    await _rtcDataChannel?.send(
      RTCDataChannelMessage(jsonEncode(screenState.toJson())),
    );
  }

  /// Workaround for local stream freezing when app is in background
  /// <br/>
  /// Ref: https://github.com/flutter-webrtc/flutter-webrtc/issues/276#issuecomment-1162536379
  Future<void> _refreshLocalStream() async {
    _localStream = await Helper.openCamera(_mediaConstraints);
    _localStream?.getVideoTracks().elementAtOrNull(0)?.enabled = isVideoOn;
    _localRTCVideoRenderer.srcObject = _localStream;
    await Future.forEach(
      _localStream?.getTracks() ?? <MediaStreamTrack>[],
      (track) async {
        if (track is VideoTrack) {
          track.enabled = isVideoOn;
        } else if (track is AudioTrack) {
          track.enabled = isAudioOn;
        }
        final senders = await _rtcPeerConnection?.getSenders();
        senders?.forEach((sender) => sender.replaceTrack(track));
      },
    );
  }

  Map<String, dynamic> get _mediaConstraints {
    return {
      'audio': isAudioOn,
      'video': isVideoOn
          ? {
              'facingMode': isFrontCameraSelected ? 'user' : 'environment',
            }
          : false,
    };
  }
}

class _RTCVideoView extends StatefulWidget {
  const _RTCVideoView({
    required this.videoRenderer,
    required this.mirror,
    required this.user,
  });

  final RTCVideoRenderer videoRenderer;
  final bool mirror;
  final PTUser? user;

  @override
  State<_RTCVideoView> createState() => _RTCVideoViewState();
}

class _RTCVideoViewState extends State<_RTCVideoView> {
  bool showUserDetails = false;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: MouseRegion(
        onEnter: (_) => setState(() => showUserDetails = true),
        onExit: (_) => setState(() => showUserDetails = false),
        child: GestureDetector(
          onTap: isDesktop
              ? null
              : () => setState(() => showUserDetails = !showUserDetails),
          child: Stack(
            children: [
              ColoredBox(
                color: Colors.black,
                child: RTCVideoView(
                  widget.videoRenderer,
                  mirror: widget.mirror,
                ),
              ),
              AnimatedSwitcher(
                duration: Durations.short3,
                child: showUserDetails
                    ? Container(
                        alignment: Alignment.bottomCenter,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              context.theme.colorScheme.surface,
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            widget.user?.name ?? '',
                            style: context.titleLarge,
                            maxLines: 3,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _controlsLog(String msg) => debugPrint('CONTROLS => $msg');
