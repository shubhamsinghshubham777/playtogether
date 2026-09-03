import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AvConnectionState { disconnected, connecting, connected, reconnecting }

/// Voice/video layer per room. Identity = Supabase user id (the token minted
/// by the livekit-token edge function enforces room membership server-side).
class LiveKitService extends ChangeNotifier {
  LiveKitService({required this.roomId, this.avLevel = AvLevel.voice});

  final String roomId;

  final AvLevel avLevel;

  /// AV is available only when the client knows the LiveKit URL; without it
  /// the whole facecam UI stays hidden.
  static bool? isConfiguredOverride;
  static bool isMockMode = false;
  static bool get isConfigured => isConfiguredOverride ?? (Env.livekitUrl ?? '').isNotEmpty;

  static bool isAvailableFor(AvLevel level) => isConfigured && level.allowsVoice;

  bool get canPublishCamera => avLevel.allowsVideo;

  static const _cameraCapture = lk.CameraCaptureOptions(
    params: lk.VideoParameters(
      dimensions: lk.VideoDimensionsPresets.h360_169,
      encoding: lk.VideoEncoding(maxFramerate: 24, maxBitrate: 400 * 1000),
    ),
  );

  lk.Room? _room;
  lk.Room? get room => _room;

  AvConnectionState _state = .disconnected;
  AvConnectionState get state => _state;

  bool get micEnabled => _room?.localParticipant?.isMicrophoneEnabled() ?? false;
  bool get camEnabled => _room?.localParticipant?.isCameraEnabled() ?? false;

  lk.LocalParticipant? get localParticipant => _room?.localParticipant;
  List<lk.RemoteParticipant> get remoteParticipants =>
      _room?.remoteParticipants.values.toList() ?? const [];

  lk.EventsListener<lk.RoomEvent>? _listener;

  Future<void> connect() async {
    if (!isAvailableFor(avLevel) || _state == .connecting || _state == .connected) return;
    _setState(.connecting);
    if (isMockMode) {
      _setState(.connected);
      return;
    }
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'livekit-token',
        body: {'room_id': roomId},
      );
      final data = (response.data as Map).cast<String, dynamic>();
      final token = data['token'] as String;
      final url = (data['url'] as String?) ?? Env.livekitUrl!;

      final room = lk.Room(
        roomOptions: const lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: _cameraCapture,
        ),
      );
      _listener = room.createListener()
        ..on<lk.RoomReconnectingEvent>((_) => _setState(.reconnecting))
        ..on<lk.RoomReconnectedEvent>((_) => _setState(.connected))
        ..on<lk.RoomDisconnectedEvent>((_) => _setState(.disconnected))
        // Track/participant churn and speaking changes all surface as change
        // notifications so tiles rebuild.
        ..on<lk.RoomEvent>((_) => notifyListeners());

      await room.connect(url, token);
      _room = room;
      _setState(.connected);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'connecting to LiveKit for room $roomId');
      _setState(.disconnected);
      rethrow;
    }
  }

  Future<void> setMicEnabled(bool enabled) async {
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
    notifyListeners();
  }

  Future<void> setCamEnabled(bool enabled) async {
    if (enabled && !canPublishCamera) return;
    await _room?.localParticipant?.setCameraEnabled(
      enabled,
      cameraCaptureOptions: enabled ? _cameraCapture : null,
    );
    notifyListeners();
  }

  void _setState(AvConnectionState state) {
    if (state != _state) {
      trace('av ${state.name}', category: 'av', data: {'room_id': roomId});
    }
    _state = state;
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _listener?.dispose();
    await _room?.disconnect();
    await _room?.dispose();
    super.dispose();
  }
}
