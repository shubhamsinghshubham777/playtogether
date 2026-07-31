import 'package:playtogether/profile/profile_models.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/sync/sync_service.dart';

class SentMessage {
  const SentMessage(this.event, this.payload);

  final String event;
  final Map<String, dynamic> payload;
}

class FakeSyncChannel implements SyncChannel {
  final handlers = <String, void Function(Map<String, dynamic>)>{};
  final sent = <SentMessage>[];
  final tracked = <Map<String, dynamic>>[];

  void Function()? presenceHandler;
  void Function(SyncSubscribeStatus, Object?)? subscribeCallback;
  List<Map<String, dynamic>> presence = const [];
  int unsubscribeCount = 0;

  List<SentMessage> sentOf(String event) => sent.where((m) => m.event == event).toList();
  SentMessage? lastOf(String event) => sentOf(event).lastOrNull;
  bool hasSent(String event) => sentOf(event).isNotEmpty;

  void deliver(String event, Map<String, dynamic> payload) => handlers[event]?.call(payload);

  void emitStatus(SyncSubscribeStatus status) => subscribeCallback?.call(status, null);

  void syncPresence(List<Map<String, dynamic>> state) {
    presence = state;
    presenceHandler?.call();
  }

  @override
  SyncChannel onBroadcast({
    required String event,
    required void Function(Map<String, dynamic>) callback,
  }) {
    handlers[event] = callback;
    return this;
  }

  @override
  SyncChannel onPresenceSync(void Function() callback) {
    presenceHandler = callback;
    return this;
  }

  @override
  void subscribe(void Function(SyncSubscribeStatus, Object?) callback) {
    subscribeCallback = callback;
  }

  @override
  Future<void> sendBroadcastMessage({
    required String event,
    required Map<String, dynamic> payload,
  }) async {
    sent.add(SentMessage(event, payload));
  }

  @override
  Future<void> track(Map<String, dynamic> payload) async => tracked.add(payload);

  @override
  List<Map<String, dynamic>> presenceState() => presence;

  @override
  Future<void> unsubscribe() async => unsubscribeCount++;
}

class FakeSyncBackend implements SyncBackend {
  final channels = <FakeSyncChannel>[];
  final insertedChat = <String>[];

  Room? roomRow;
  MembershipRow? membership;
  List<ChatMessage> chatHistory = const [];

  FakeSyncChannel get channelInUse => channels.last;

  @override
  SyncChannel channel(String topic) {
    final created = FakeSyncChannel();
    channels.add(created);
    return created;
  }

  @override
  Future<MembershipRow?> loadMembership(String roomId, String userId) async => membership;

  @override
  Future<Room?> fetchRoom(String roomId) async => roomRow;

  @override
  Future<List<ChatMessage>> loadChatHistory(String roomId) async => chatHistory;

  @override
  Future<void> insertChatMessage({
    required String roomId,
    required String senderId,
    required String content,
  }) async => insertedChat.add(content);
}

class FakeSyncPlayer implements SyncPlayer {
  Duration positionValue = Duration.zero;
  Duration durationValue = Duration.zero;
  bool playingValue = false;

  int playCount = 0;
  int pauseCount = 0;
  final seeks = <Duration>[];

  @override
  Duration get position => positionValue;

  @override
  Duration get duration => durationValue;

  @override
  bool get playing => playingValue;

  @override
  void play() => playCount++;

  @override
  void pause() => pauseCount++;

  @override
  void seek(Duration position) => seeks.add(position);
}

Room testRoom({String id = 'room-1', RoomMedia media = RoomMedia.none}) => Room(
  id: id,
  code: 'ABC123',
  name: 'Movie night',
  createdBy: 'host',
  createdAt: DateTime.utc(2026, 7, 31, 10),
  durationMinutes: 120,
  expiresAt: DateTime.utc(2026, 7, 31, 12),
  mediaKind: media.kind,
  mediaName: media.name,
  mediaDuration: media.duration,
  mediaUrl: media.url,
  mediaUpdatedAt: media.updatedAt,
);

Profile testProfile(String id) =>
    Profile(id: id, displayName: id, isGuest: false);

Map<String, dynamic> presenceEntry(
  String userId, {
  String role = 'member',
  int joinedSeconds = 0,
  String ready = 'none',
  String? file,
}) => {
  'user_id': userId,
  'display_name': userId,
  'role': role,
  'joined_at': DateTime.utc(2026, 7, 31, 10).add(Duration(seconds: joinedSeconds)).toIso8601String(),
  'ready_status': ready,
  'loaded_file_name': file,
};
