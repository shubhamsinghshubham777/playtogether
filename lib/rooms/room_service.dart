import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'room_models.dart';

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
    final row = await _client.rpc(
      'create_room',
      params: {'p_name': name, 'p_duration_minutes': durationMinutes},
    );
    final room = Room.fromJson(_singleRow(row));
    _currentRoom = room;
    notifyListeners();
    return room;
  }

  Future<Room> joinRoom(String code) async {
    final row = await _client.rpc('join_room', params: {'p_code': code});
    final room = Room.fromJson(_singleRow(row));
    _currentRoom = room;
    notifyListeners();
    return room;
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

  void clear() {
    _currentRoom = null;
    pendingJoinCode = null;
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
