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
import 'package:playtogether/features/call/model/call_screen_state.dart';
import 'package:playtogether/features/call/view/pt_video_controls.dart';

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
    WidgetsBinding.instance.removeObserver(this);
    _docExistanceListener?.cancel();
    _candidateListener?.cancel();
    _deleteCallRelatedData();
    _localRTCVideoRenderer.dispose();
    _remoteRTCVideoRenderer.dispose();
    _localStream?.dispose();
    _rtcDataChannel?.close();
    _rtcPeerConnection?.dispose();

    // Video Player
    try {
      videoPlayer.dispose();
    } catch (e, st) {
      debugPrint('Error while disposing video player: ${e.toString()}');
      debugPrintStack(stackTrace: st);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Column(
        children: [
          Text(
            'Caller: ${widget.callerUid}'
            '\nCallee: ${widget.calleeUid}'
            '\nIs calling or being called?: '
            '${widget.offer != null ? 'Being called' : 'Calling'}'
            '\nCurrent message: $screenState',
          ),
          FilledButton(
            onPressed: () async {
              FilePickerResult? result = await FilePicker.platform.pickFiles();
              if (result != null) {
                videoPlayer.open(Media(result.files.single.path!), play: false);
                _updateScreenState(
                  screenState.copyWith(videoName: result.files.single.name),
                );
              }
            },
            child: const Text('Open'),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500),
            child: AspectRatio(
              aspectRatio: 16 / 9,
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
          Expanded(
            child: GridView(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
              ),
              children: [
                RTCVideoView(_localRTCVideoRenderer, mirror: true),
                RTCVideoView(_remoteRTCVideoRenderer),
              ],
            ),
          ),
        ],
      ),
    );
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

  Future<void> _deleteCallRelatedData() async {
    debugPrint('Deleting doc having id: ${widget.calleeUid}');

    final docToDelete =
        FirebaseFirestore.instance.collection('calls').doc(widget.calleeUid);

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

void _controlsLog(String msg) => debugPrint('CONTROLS => $msg');
