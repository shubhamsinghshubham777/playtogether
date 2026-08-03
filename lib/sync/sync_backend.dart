import 'package:media_kit/media_kit.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/rooms/room_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_logic.dart';

enum SyncSubscribeStatus { subscribed, channelError, closed, timedOut }

/// Everything [SyncService] needs from a Realtime channel, narrowed to the
/// eight calls it actually makes. Narrow on purpose: a fake of this is cheap,
/// and it does not drift when supabase_flutter moves.
abstract interface class SyncChannel {
  SyncChannel onBroadcast({
    required String event,
    required void Function(Map<String, dynamic> payload) callback,
  });
  SyncChannel onPresenceSync(void Function() callback);
  void subscribe(void Function(SyncSubscribeStatus status, Object? error) callback);
  Future<void> sendBroadcastMessage({required String event, required Map<String, dynamic> payload});
  Future<void> track(Map<String, dynamic> payload);

  /// Flattened across devices — one entry per connection, not per user. The
  /// per-user collapse is [mergePresence]'s job.
  List<Map<String, dynamic>> presenceState();
  Future<void> unsubscribe();
}

class MembershipRow {
  const MembershipRow({required this.role, required this.joinedAt});

  final String role;
  final DateTime joinedAt;
}

/// The rest of the room's server surface. Bundled with the channel into one
/// seam so a test needs exactly one fake.
abstract interface class SyncBackend {
  SyncChannel channel(String topic);
  Future<MembershipRow?> loadMembership(String roomId, String userId);
  Future<Room?> fetchRoom(String roomId);
  Future<List<ChatMessage>> loadChatHistory(String roomId);
  Future<void> insertChatMessage({
    required String roomId,
    required String senderId,
    required String content,
  });
}

/// The playback surface the sync layer touches. [SyncService]'s
/// `onRemotePlay`/`onRemotePause`/`onRemoteSeek` hooks override most of it at
/// runtime, but the `state_request` media check reads it unconditionally.
abstract interface class SyncPlayer {
  Duration get position;
  Duration get duration;
  bool get playing;
  void play();
  void pause();
  void seek(Duration position);
}

class MediaKitSyncPlayer implements SyncPlayer {
  MediaKitSyncPlayer(this._player);

  final Player _player;

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  bool get playing => _player.state.playing;

  @override
  void play() => _player.play();

  @override
  void pause() => _player.pause();

  @override
  void seek(Duration position) => _player.seek(position);
}

class SupabaseSyncChannel implements SyncChannel {
  SupabaseSyncChannel(this._channel);

  final RealtimeChannel _channel;

  @override
  SyncChannel onBroadcast({
    required String event,
    required void Function(Map<String, dynamic>) callback,
  }) {
    _channel.onBroadcast(event: event, callback: callback);
    return this;
  }

  @override
  SyncChannel onPresenceSync(void Function() callback) {
    _channel.onPresenceSync((_) => callback());
    return this;
  }

  @override
  void subscribe(void Function(SyncSubscribeStatus, Object?) callback) {
    _channel.subscribe((status, error) {
      callback(switch (status) {
        RealtimeSubscribeStatus.subscribed => SyncSubscribeStatus.subscribed,
        RealtimeSubscribeStatus.channelError => SyncSubscribeStatus.channelError,
        RealtimeSubscribeStatus.closed => SyncSubscribeStatus.closed,
        RealtimeSubscribeStatus.timedOut => SyncSubscribeStatus.timedOut,
      }, error);
    });
  }

  @override
  Future<void> sendBroadcastMessage({
    required String event,
    required Map<String, dynamic> payload,
  }) => _channel.sendBroadcastMessage(event: event, payload: payload);

  @override
  Future<void> track(Map<String, dynamic> payload) => _channel.track(payload);

  @override
  List<Map<String, dynamic>> presenceState() => _channel
      .presenceState()
      .expand((state) => state.presences)
      .map((presence) => presence.payload)
      .toList();

  @override
  Future<void> unsubscribe() => _channel.unsubscribe();
}

class SupabaseSyncBackend implements SyncBackend {
  const SupabaseSyncBackend();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  SyncChannel channel(String topic) => SupabaseSyncChannel(
    _client.channel(topic, opts: const RealtimeChannelConfig(self: false, private: true)),
  );

  @override
  Future<MembershipRow?> loadMembership(String roomId, String userId) async {
    final row = await _client
        .from('room_members')
        .select('role, joined_at')
        .eq('room_id', roomId)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return MembershipRow(
      role: row['role'] as String,
      joinedAt: DateTime.parse(row['joined_at'] as String),
    );
  }

  @override
  Future<Room?> fetchRoom(String roomId) => RoomService.instance.fetchRoom(roomId);

  @override
  Future<List<ChatMessage>> loadChatHistory(String roomId) async {
    final rows = await _client
        .from('messages')
        .select('sender_id, content, created_at, profiles(display_name)')
        .eq('room_id', roomId)
        .order('created_at', ascending: true)
        .limit(300);
    return rows.map<ChatMessage>((r) {
      return ChatMessage(
        senderId: r['sender_id'] as String,
        displayName:
            (r['profiles'] as Map<String, dynamic>?)?['display_name'] as String? ?? 'Watcher',
        content: r['content'] as String,
        sentAt: DateTime.parse(r['created_at'] as String),
      );
    }).toList();
  }

  @override
  Future<void> insertChatMessage({
    required String roomId,
    required String senderId,
    required String content,
  }) => _client.from('messages').insert({
    'room_id': roomId,
    'sender_id': senderId,
    'content': content,
  });
}
