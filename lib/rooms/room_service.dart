import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:playtogether/analytics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'room_models.dart';

enum RoomJoinSource { code, deeplink }

class RoomService extends ChangeNotifier {
  RoomService._();
  static final instance = RoomService._();

  SupabaseClient get _client => Supabase.instance.client;

  Room? _currentRoom;
  Room? get currentRoom => _currentRoom;

  /// Difference between server clock and local clock; add to local now() for
  /// expiry math so a lying client clock can't skew the countdown.
  Duration _serverOffset = Duration.zero;
  Duration get serverOffset => _serverOffset;

  DateTime get serverNow => DateTime.now().add(_serverOffset);

  /// Deep-link join code parked until the user is signed in.
  String? pendingJoinCode;

  Future<void> syncServerTime() async {
    final before = DateTime.now();
    final raw = await _client.rpc('get_server_time');
    final after = DateTime.now();
    final server = DateTime.parse(raw as String);
    final midpoint = before.add(after.difference(before) ~/ 2);
    _serverOffset = server.difference(midpoint);
  }

  Future<Room> createRoom({required String name, required int durationMinutes}) async {
    try {
      final row = await _client.rpc(
        'create_room',
        params: {'p_name': name, 'p_duration_minutes': durationMinutes},
      );
      final room = Room.fromJson(_singleRow(row));
      _currentRoom = room;
      notifyListeners();
      Analytics.instance.track('room_created', {
        'duration_min': durationMinutes,
        'room_id': room.id,
        'max_members': room.maxMembers,
        'av_level': room.avLevel.name,
        'persistent': room.persistent,
      });
      if (durationMinutes >= kRoomDurationCapMinutes) {
        Analytics.instance.track('limit_hit', {'which': 'duration_cap'});
      }
      return room;
    } catch (e) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .guestRoomLimit) {
        Analytics.instance.track('limit_hit', {'which': 'guest_room_limit'});
      } else if (failure == .roomLimitReached) {
        Analytics.instance.track('limit_hit', {'which': 'room_limit'});
      } else if (failure == .invalidDuration) {
        Analytics.instance.track('limit_hit', {'which': 'duration_cap'});
      }
      rethrow;
    }
  }

  Future<Room> joinRoom(String code, {RoomJoinSource via = RoomJoinSource.code}) async {
    try {
      final row = await _client.rpc('join_room', params: {'p_code': code});
      final room = Room.fromJson(_singleRow(row));
      _currentRoom = room;
      notifyListeners();
      Analytics.instance.track('room_joined', {'via': via.name, 'room_id': room.id});
      return room;
    } catch (e) {
      final failure = RoomErrorCode.fromError(e);
      Analytics.instance.track('room_join_failed', {'reason': failure.code});
      if (failure == .roomFull) {
        Analytics.instance.track('limit_hit', {'which': 'member_cap'});
      }
      rethrow;
    }
  }

  Future<Room?> fetchRoom(String roomId) async {
    final row = await _client.from('rooms').select().eq('id', roomId).maybeSingle();
    final room = row != null ? Room.fromJson(row) : null;
    if (room != null && _currentRoom?.id == room.id) {
      _currentRoom = room;
    }
    return room;
  }

  /// The guest's still-live hosted room, if any (drives the room-limit dialog).
  Future<Room?> fetchLiveHostedRoom() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final rows = await _client
        .from('rooms')
        .select()
        .eq('created_by', uid)
        .filter('ended_at', 'is', null)
        .gt('expires_at', serverNow.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Room.fromJson(rows.first);
  }

  Future<void> leaveRoom(String roomId) async {
    await _client.rpc('leave_room', params: {'p_room_id': roomId});
    if (_currentRoom?.id == roomId) {
      _currentRoom = null;
      notifyListeners();
    }
  }

  Future<void> endRoom(String roomId) async {
    await _client.rpc('end_room', params: {'p_room_id': roomId});
  }

  List<MyRoom> _myRooms = const [];
  List<MyRoom> get myRooms => _myRooms;

  bool _loadingMyRooms = false;
  bool get loadingMyRooms => _loadingMyRooms;

  Future<List<MyRoom>> loadMyRooms() async {
    _loadingMyRooms = true;
    notifyListeners();
    try {
      final rows = await _client.rpc('list_my_rooms');
      final list = (rows as List? ?? const [])
          .map<MyRoom>((r) => MyRoom.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
      _myRooms = list;
      return list;
    } finally {
      _loadingMyRooms = false;
      notifyListeners();
    }
  }

  Future<Room> extendRoom({required String roomId, required int minutes}) async {
    try {
      final row = await _client.rpc(
        'extend_room',
        params: {'p_room_id': roomId, 'p_minutes': minutes},
      );
      final room = _adopt(Room.fromJson(_singleRow(row)));
      Analytics.instance.track('room_extended', {
        'room_id': roomId,
        'added_min': minutes,
        'total_min': room.durationMinutes,
      });
      return room;
    } catch (e) {
      final failure = RoomErrorCode.fromError(e);
      if (failure == .extensionUsed || failure == .extensionCap) {
        Analytics.instance.track('limit_hit', {'which': failure.code});
      }
      rethrow;
    }
  }

  Future<Room> resumeRoom({required String roomId, required int minutes}) async {
    final row = await _client.rpc(
      'resume_room',
      params: {'p_room_id': roomId, 'p_minutes': minutes},
    );
    final room = _adopt(Room.fromJson(_singleRow(row)));
    Analytics.instance.track('room_resumed', {'room_id': roomId, 'duration_min': minutes});
    return room;
  }

  Future<void> deleteRoom(String roomId) async {
    await _client.rpc('delete_room', params: {'p_room_id': roomId});
    _myRooms = _myRooms.where((r) => r.room.id != roomId).toList();
    if (_currentRoom?.id == roomId) _currentRoom = null;
    Analytics.instance.track('room_deleted', {'room_id': roomId});
    notifyListeners();
  }

  Future<bool> updateMediaPosition({required String roomId, required Duration position}) async {
    try {
      await _client.rpc(
        'update_media_position',
        params: {'p_room_id': roomId, 'p_position_ms': position.inMilliseconds},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Host only. Passing [kind] `.none` clears the room's media entirely.
  Future<Room> setRoomMedia({
    required String roomId,
    required RoomMediaKind kind,
    String? name,
    Duration? duration,
    String? url,
  }) async {
    final row = await _client.rpc(
      'set_room_media',
      params: {
        'p_room_id': roomId,
        'p_kind': kind.wire,
        'p_name': name,
        'p_duration_ms': duration?.inMilliseconds,
        'p_url': url,
      },
    );
    return _adopt(Room.fromJson(_singleRow(row)));
  }

  /// Host only.
  Future<Room> setTransportLock({required String roomId, required bool locked}) async {
    final row = await _client.rpc(
      'set_transport_lock',
      params: {'p_room_id': roomId, 'p_locked': locked},
    );
    return _adopt(Room.fromJson(_singleRow(row)));
  }

  /// Host only. Removing the member's row does not eject them from the realtime
  /// channel — Realtime authorizes at subscribe time — so the caller must also
  /// broadcast `member_kicked`.
  Future<void> kickMember({
    required String roomId,
    required String userId,
    required bool allowRejoin,
  }) async {
    await _client.rpc(
      'kick_member',
      params: {'p_room_id': roomId, 'p_target_user_id': userId, 'p_ban': !allowRejoin},
    );
  }

  Future<List<RoomMember>> fetchMembers(String roomId) async {
    final rows = await _client
        .from('room_members')
        .select('*, profiles(*)')
        .eq('room_id', roomId)
        .order('joined_at', ascending: true);
    return rows.map<RoomMember>((r) => RoomMember.fromJson(r)).toList();
  }

  void noteRoomExited() {
    if (_currentRoom == null) return;
    _currentRoom = null;
    notifyListeners();
  }

  void clear() {
    _currentRoom = null;
    pendingJoinCode = null;
    _myRooms = const [];
    notifyListeners();
  }

  Room _adopt(Room room) {
    if (_currentRoom?.id == room.id) {
      _currentRoom = room;
      notifyListeners();
    }
    return room;
  }

  // rpc() returning `setof`/record can come back as a single map or a
  // one-element list depending on the function shape.
  Map<String, dynamic> _singleRow(dynamic row) {
    if (row is List) return (row.first as Map).cast<String, dynamic>();
    return (row as Map).cast<String, dynamic>();
  }
}
