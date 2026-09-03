import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/av/livekit_service.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/room_service.dart';
import 'package:synctogether/sync/sync_service.dart';

/// Mock user & session representing the local user.
final mockCurrentUser = User.fromJson({
  'id': 'user-alex',
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'alex@synctogether.app',
  'email_confirmed_at': '2026-01-01T00:00:00Z',
  'app_metadata': {},
  'user_metadata': {'full_name': 'Alex Rivers'},
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

final mockCurrentSession = Session.fromJson({
  'access_token': 'mock-access-token',
  'token_type': 'bearer',
  'user': {
    'id': 'user-alex',
    'aud': 'authenticated',
    'email': 'alex@synctogether.app',
    'app_metadata': {},
    'user_metadata': {'full_name': 'Alex Rivers'},
    'created_at': '2026-01-01T00:00:00Z',
  },
});

const mockCurrentProfile = Profile(
  id: 'user-alex',
  displayName: 'Alex Rivers',
  isGuest: false,
  email: 'alex@synctogether.app',
);

final mockRoomOne = Room(
  id: 'demo-room-1',
  name: 'Interstellar Movie Night',
  code: 'X7K9P2',
  createdBy: 'user-alex',
  durationMinutes: 150,
  maxMembers: 8,
  avLevel: .video,
  mediaKind: .local,
  mediaName: 'Interstellar.2014.2160p.UHD.mkv',
  mediaDuration: const Duration(hours: 2, minutes: 49, seconds: 3),
  persistent: true,
  createdAt: DateTime.now().subtract(const Duration(minutes: 84)),
  expiresAt: DateTime.now().add(const Duration(minutes: 66)),
);

final mockRoomTwo = Room(
  id: 'demo-room-2',
  name: 'Cyberpunk Anime Night',
  code: 'K4M8Y1',
  createdBy: 'user-alex',
  durationMinutes: 120,
  maxMembers: 8,
  avLevel: .voice,
  mediaKind: .local,
  mediaName: 'Edgerunners_Ep04_1080p.mp4',
  mediaDuration: const Duration(minutes: 24, seconds: 10),
  persistent: true,
  createdAt: DateTime.now().subtract(const Duration(hours: 5)),
  expiresAt: DateTime.now().add(const Duration(hours: 19)),
);

final mockRoomThree = Room(
  id: 'demo-room-3',
  name: 'Studio Ghibli Favorites',
  code: 'N9P2L5',
  createdBy: 'user-alex',
  durationMinutes: 180,
  maxMembers: 8,
  avLevel: .voice,
  mediaKind: .local,
  mediaName: 'Spirited_Away_Remaster.mkv',
  mediaDuration: const Duration(hours: 2, minutes: 5),
  persistent: true,
  createdAt: DateTime.now().subtract(const Duration(days: 1)),
  expiresAt: DateTime.now().add(const Duration(hours: 12)),
);

final mockMembersList = [
  RoomMember(
    roomId: 'demo-room-1',
    userId: 'user-alex',
    role: 'host',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 84)),
    profile: const Profile(id: 'user-alex', displayName: 'Alex Rivers', isGuest: false),
  ),
  RoomMember(
    roomId: 'demo-room-1',
    userId: 'user-sarah',
    role: 'member',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 75)),
    profile: const Profile(id: 'user-sarah', displayName: 'Sarah Chen', isGuest: false),
  ),
  RoomMember(
    roomId: 'demo-room-1',
    userId: 'user-david',
    role: 'member',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 60)),
    profile: const Profile(id: 'user-david', displayName: 'David Kim', isGuest: false),
  ),
  RoomMember(
    roomId: 'demo-room-1',
    userId: 'user-elena',
    role: 'guest',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 40)),
    profile: const Profile(id: 'user-elena', displayName: 'Elena Rostova', isGuest: true),
  ),
];

final mockPresentList = [
  PresentMember(
    userId: 'user-alex',
    displayName: 'Alex Rivers',
    role: 'host',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 84)),
    readyStatus: .ready,
    loadedFileName: 'Interstellar.2014.2160p.UHD.mkv',
  ),
  PresentMember(
    userId: 'user-sarah',
    displayName: 'Sarah Chen',
    role: 'member',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 75)),
    readyStatus: .ready,
    loadedFileName: 'Interstellar.2014.2160p.UHD.mkv',
  ),
  PresentMember(
    userId: 'user-david',
    displayName: 'David Kim',
    role: 'member',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 60)),
    readyStatus: .ready,
    loadedFileName: 'Interstellar.2014.2160p.UHD.mkv',
  ),
  PresentMember(
    userId: 'user-elena',
    displayName: 'Elena Rostova',
    role: 'guest',
    joinedAt: DateTime.now().subtract(const Duration(minutes: 40)),
    readyStatus: .ready,
    loadedFileName: 'Interstellar.2014.2160p.UHD.mkv',
  ),
];

final mockChatMessagesList = [
  ChatMessage(
    senderId: 'user-david',
    displayName: 'David Kim',
    content: 'Audio and video are locked in down to the millisecond!',
    sentAt: DateTime.now().subtract(const Duration(minutes: 3)),
  ),
  ChatMessage(
    senderId: 'user-sarah',
    displayName: 'Sarah Chen',
    content: 'The color grading in this cosmic sequence is unbelievable!',
    sentAt: DateTime.now().subtract(const Duration(minutes: 2)),
  ),
  ChatMessage(
    senderId: 'user-alex',
    displayName: 'Alex Rivers',
    content: 'Wait for the wormhole transition at 01:25:00... pure chills.',
    sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
  ),
  ChatMessage(
    senderId: 'user-elena',
    displayName: 'Elena Rostova',
    content: 'Watching right from my laptop as a guest, zero lag at all!',
    sentAt: DateTime.now().subtract(const Duration(seconds: 25)),
  ),
];

class MockAuthService extends AuthService {
  @override
  Session? get session => mockCurrentSession;

  @override
  User? get user => mockCurrentUser;

  @override
  bool get isSignedIn => true;

  @override
  bool get isGuest => false;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();

  @override
  Stream<String> get failures => const Stream.empty();

  @override
  void start() {}
}

class MockProfileService extends ProfileService {
  @override
  Profile? get profile => mockCurrentProfile;

  @override
  Future<Profile?> load() async => mockCurrentProfile;
}

class MockEntitlementService extends EntitlementService {
  static const mockTierLimits = TierLimits(
    tier: kPremiumTier,
    maxLiveRooms: 8,
    maxMembers: 16,
    maxSessionMinutes: 600,
    maxTotalSessionMinutes: 600,
    avLevel: .video,
    persistentRoomCap: 5,
    dormantHours: 72,
    freeExtensionMinutes: 120,
    mediaSharing: 'full',
    mediaSharingWeeklyBytes: 10737418240,
  );

  @override
  TierLimits? get limits => mockTierLimits;

  @override
  TierLimits get limitsOrFallback => mockTierLimits;

  @override
  String get tier => mockTierLimits.tier;

  @override
  bool get isPremium => true;

  @override
  Future<TierLimits?> load() async => mockTierLimits;

  @override
  Future<TierLimits?> refresh() async => mockTierLimits;
}

class MockRoomService extends RoomService {
  late final List<MyRoom> _rooms = [
    MyRoom(
      room: mockRoomOne,
      state: .live,
      role: 'host',
      memberCount: 4,
      isOwner: true,
      isMember: true,
    ),
    MyRoom(
      room: mockRoomTwo,
      state: .dormant,
      role: 'host',
      memberCount: 3,
      isOwner: true,
      isMember: true,
    ),
    MyRoom(
      room: mockRoomThree,
      state: .dormant,
      role: 'host',
      memberCount: 6,
      isOwner: true,
      isMember: true,
    ),
  ];

  @override
  List<MyRoom> get myRooms => _rooms;

  @override
  bool get loadingMyRooms => false;

  @override
  Future<List<MyRoom>> loadMyRooms() async => _rooms;

  @override
  Future<Room?> fetchRoom(String roomId) async {
    final match = _rooms.where((r) => r.room.id == roomId).firstOrNull;
    return match?.room ?? mockRoomOne;
  }

  @override
  Future<List<RoomMember>> fetchMembers(String roomId) async => mockMembersList;

  @override
  Future<Map<String, String>> fetchMemberTiers(String roomId) async => {
    'user-alex': 'premium',
    'user-sarah': 'premium',
    'user-david': 'free',
    'user-elena': 'guest',
  };

  @override
  Future<void> syncServerTime() async {}

  @override
  DateTime get serverNow => DateTime.now();

  @override
  Future<Room> resumeRoom({required String roomId, required int minutes}) async {
    final r = await fetchRoom(roomId);
    return r!;
  }

  @override
  Future<Room> createRoom({
    required String name,
    required int durationMinutes,
    String? stagedId,
  }) async {
    return mockRoomOne;
  }

  @override
  Future<Room> joinRoom(String code, {RoomJoinSource via = RoomJoinSource.code}) async {
    return mockRoomOne;
  }

  @override
  Future<Room> setRoomMedia({
    required String roomId,
    required RoomMediaKind kind,
    String? name,
    Duration? duration,
    String? url,
  }) async {
    return mockRoomOne;
  }
}

class MockSyncChannel implements SyncChannel {
  MockSyncChannel({required this.presence, required this.chatHistory});

  final List<PresentMember> presence;
  final List<ChatMessage> chatHistory;

  final handlers = <String, void Function(Map<String, dynamic>)>{};
  void Function()? presenceHandler;
  void Function(SyncSubscribeStatus, Object?)? subscribeCallback;

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
    Future.microtask(callback);
    return this;
  }

  @override
  void subscribe(void Function(SyncSubscribeStatus, Object?) callback) {
    subscribeCallback = callback;
    Future.microtask(() => callback(SyncSubscribeStatus.subscribed, null));
  }

  @override
  Future<void> sendBroadcastMessage({
    required String event,
    required Map<String, dynamic> payload,
  }) async {
    handlers[event]?.call(payload);
  }

  @override
  Future<void> track(Map<String, dynamic> payload) async {}

  @override
  List<Map<String, dynamic>> presenceState() {
    return presence.map((p) => {
      'user_id': p.userId,
      'display_name': p.displayName,
      'role': p.role,
      'joined_at': p.joinedAt.toIso8601String(),
      'ready_status': p.readyStatus.name,
      'loaded_file_name': p.loadedFileName,
    }).toList();
  }

  @override
  Future<void> unsubscribe() async {}
}

class MockSyncBackend implements SyncBackend {
  MockSyncBackend({
    required this.room,
    required this.presence,
    required this.chatHistory,
  });

  final Room room;
  final List<PresentMember> presence;
  final List<ChatMessage> chatHistory;

  @override
  SyncChannel channel(String topic) {
    return MockSyncChannel(presence: presence, chatHistory: chatHistory);
  }

  @override
  Future<MembershipRow?> loadMembership(String roomId, String userId) async {
    return MembershipRow(
      role: 'host',
      joinedAt: DateTime.now().subtract(const Duration(minutes: 84)),
    );
  }

  @override
  Future<Room?> fetchRoom(String roomId) async => room;

  @override
  Future<List<ChatMessage>> loadChatHistory(String roomId) async => chatHistory;

  @override
  Future<void> insertChatMessage({
    required String roomId,
    required String senderId,
    required String content,
  }) async {
    chatHistory.add(ChatMessage(
      senderId: senderId,
      displayName: 'Alex Rivers',
      content: content,
      sentAt: DateTime.now(),
    ));
  }
}

/// Installs mock dependency overrides across all services.
void installMockDependencies() {
  AuthService.instance = MockAuthService();
  ProfileService.instance = MockProfileService();
  EntitlementService.instance = MockEntitlementService();
  RoomService.instance = MockRoomService();
  SyncService.defaultBackendOverride = MockSyncBackend(
    room: mockRoomOne,
    presence: mockPresentList,
    chatHistory: mockChatMessagesList,
  );
  LiveKitService.isConfiguredOverride = true;
  LiveKitService.isMockMode = true;
}
