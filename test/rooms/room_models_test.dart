import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/rooms/room_models.dart';

Map<String, dynamic> _minimalRow() => {
  'id': 'r1',
  'code': 'ABC123',
  'name': 'Movie night',
  'created_by': 'u1',
  'created_at': '2026-07-31T10:00:00.000Z',
  'duration_minutes': 120,
  'expires_at': '2026-07-31T12:00:00.000Z',
};

void main() {
  group('RoomMediaKind.fromWire', () {
    test('maps the two real kinds', () {
      expect(RoomMediaKind.fromWire('local'), RoomMediaKind.local);
      expect(RoomMediaKind.fromWire('youtube'), RoomMediaKind.youtube);
    });

    test('falls back to none for null, empty, unknown and wrong case', () {
      expect(RoomMediaKind.fromWire(null), RoomMediaKind.none);
      expect(RoomMediaKind.fromWire(''), RoomMediaKind.none);
      expect(RoomMediaKind.fromWire('none'), RoomMediaKind.none);
      expect(RoomMediaKind.fromWire('vimeo'), RoomMediaKind.none);
      expect(RoomMediaKind.fromWire('Local'), RoomMediaKind.none);
      expect(RoomMediaKind.fromWire('LOCAL'), RoomMediaKind.none);
    });

    test('wire is the inverse of fromWire for every kind', () {
      for (final kind in RoomMediaKind.values) {
        expect(RoomMediaKind.fromWire(kind.wire), kind);
      }
    });
  });

  group('Room.fromJson', () {
    test('reads a full row', () {
      final room = Room.fromJson({
        ..._minimalRow(),
        'ended_at': '2026-07-31T11:00:00.000Z',
        'media_kind': 'local',
        'media_name': 'movie.mkv',
        'media_duration_ms': 7200000,
        'media_url': null,
        'media_updated_at': '2026-07-31T10:30:00.000Z',
        'transport_lock': true,
      });

      expect(room.id, 'r1');
      expect(room.code, 'ABC123');
      expect(room.name, 'Movie night');
      expect(room.createdBy, 'u1');
      expect(room.durationMinutes, 120);
      expect(room.expiresAt, DateTime.utc(2026, 7, 31, 12));
      expect(room.endedAt, DateTime.utc(2026, 7, 31, 11));
      expect(room.mediaKind, RoomMediaKind.local);
      expect(room.mediaName, 'movie.mkv');
      expect(room.mediaDuration, const Duration(milliseconds: 7200000));
      expect(room.mediaUrl, isNull);
      expect(room.mediaUpdatedAt, DateTime.utc(2026, 7, 31, 10, 30));
      expect(room.transportLock, isTrue);
      expect(room.hasMedia, isTrue);
    });

    test('reads a minimal row, defaulting media and the transport lock', () {
      final room = Room.fromJson(_minimalRow());

      expect(room.endedAt, isNull);
      expect(room.mediaKind, RoomMediaKind.none);
      expect(room.mediaName, isNull);
      expect(room.mediaDuration, isNull);
      expect(room.mediaUrl, isNull);
      expect(room.mediaUpdatedAt, isNull);
      expect(room.transportLock, isFalse);
      expect(room.hasMedia, isFalse);
    });

    test('accepts media_duration_ms as a double, since num.toInt() absorbs it', () {
      final room = Room.fromJson({
        ..._minimalRow(),
        'media_kind': 'local',
        'media_duration_ms': 7200000.0,
      });
      expect(room.mediaDuration, const Duration(milliseconds: 7200000));
    });

    test('a null transport_lock reads as unlocked rather than throwing', () {
      final room = Room.fromJson({..._minimalRow(), 'transport_lock': null});
      expect(room.transportLock, isFalse);
    });

    test('builds the invite link from the code', () {
      final room = Room.fromJson(_minimalRow());
      expect(room.inviteLink, 'playtogether://join/ABC123');
    });
  });

  group('RoomMedia.isNewerThan', () {
    RoomMedia at(DateTime? stamp) =>
        RoomMedia(kind: RoomMediaKind.local, name: 'a.mkv', updatedAt: stamp);

    final earlier = DateTime.utc(2026, 7, 31, 10);
    final later = DateTime.utc(2026, 7, 31, 11);

    test('a strictly later stamp wins', () {
      expect(at(later).isNewerThan(at(earlier)), isTrue);
    });

    test('an earlier stamp loses', () {
      expect(at(earlier).isNewerThan(at(later)), isFalse);
    });

    test('equal stamps lose, so a re-delivered broadcast never re-adopts', () {
      expect(at(later).isNewerThan(at(later)), isFalse);
    });

    test('a stamp one millisecond apart is enough to win', () {
      final tick = later.add(const Duration(milliseconds: 1));
      expect(at(tick).isNewerThan(at(later)), isTrue);
      expect(at(later).isNewerThan(at(tick)), isFalse);
    });

    test('unstamped media never wins, so a never-set refetch cannot wipe media', () {
      expect(at(null).isNewerThan(at(later)), isFalse);
      expect(RoomMedia.none.isNewerThan(at(later)), isFalse);
    });

    test('any stamp beats unstamped, so the first set is always adopted', () {
      expect(at(earlier).isNewerThan(at(null)), isTrue);
      expect(at(earlier).isNewerThan(RoomMedia.none), isTrue);
    });

    test('unstamped against unstamped loses', () {
      expect(at(null).isNewerThan(at(null)), isFalse);
      expect(RoomMedia.none.isNewerThan(RoomMedia.none), isFalse);
    });

    test('a late refetch cannot clobber a newer broadcast already applied', () {
      final applied = at(later);
      final staleRefetch = at(earlier);
      expect(staleRefetch.isNewerThan(applied), isFalse);
    });

    test('ordering ignores clock skew in kind, name and url', () {
      final a = RoomMedia(kind: RoomMediaKind.youtube, url: 'https://y/1', updatedAt: later);
      final b = RoomMedia(kind: RoomMediaKind.local, name: 'z.mkv', updatedAt: earlier);
      expect(a.isNewerThan(b), isTrue);
      expect(b.isNewerThan(a), isFalse);
    });
  });

  group('RoomMedia', () {
    test('none is not set; a real kind is', () {
      expect(RoomMedia.none.isSet, isFalse);
      expect(const RoomMedia(kind: RoomMediaKind.local, name: 'a.mkv').isSet, isTrue);
      expect(const RoomMedia(kind: RoomMediaKind.youtube, url: 'https://y/1').isSet, isTrue);
    });

    test('fromRoom carries every media field and nothing else', () {
      final room = Room.fromJson({
        ..._minimalRow(),
        'media_kind': 'youtube',
        'media_url': 'https://youtu.be/abc',
        'media_updated_at': '2026-07-31T10:30:00.000Z',
      });
      final media = RoomMedia.fromRoom(room);

      expect(media.kind, RoomMediaKind.youtube);
      expect(media.url, 'https://youtu.be/abc');
      expect(media.updatedAt, DateTime.utc(2026, 7, 31, 10, 30));
      expect(media.name, isNull);
      expect(media.duration, isNull);
    });
  });

  group('RoomMember.fromJson', () {
    test('reads a row with a joined profile', () {
      final member = RoomMember.fromJson({
        'room_id': 'r1',
        'user_id': 'u1',
        'role': 'host',
        'joined_at': '2026-07-31T10:00:00.000Z',
        'profiles': {'id': 'u1', 'display_name': 'Ada', 'is_guest': false},
      });

      expect(member.userId, 'u1');
      expect(member.isHost, isTrue);
      expect(member.displayName, 'Ada');
      expect(member.joinedAt, DateTime.utc(2026, 7, 31, 10));
    });

    test('falls back to Watcher when no profile is joined in', () {
      final member = RoomMember.fromJson({
        'room_id': 'r1',
        'user_id': 'u2',
        'role': 'member',
        'joined_at': '2026-07-31T10:05:00.000Z',
      });

      expect(member.isHost, isFalse);
      expect(member.displayName, 'Watcher');
      expect(member.profile, isNull);
    });
  });

  group('RoomErrorCode.fromError', () {
    test('maps every declared code from a wrapped error string', () {
      for (final value in RoomErrorCode.values) {
        if (value == RoomErrorCode.unknown) continue;
        final error = Exception('PostgrestException(message: ${value.code}, code: P0001)');
        expect(RoomErrorCode.fromError(error), value, reason: value.code);
      }
    });

    test('falls back to unknown for an unrecognised error', () {
      expect(RoomErrorCode.fromError(Exception('connection reset by peer')), RoomErrorCode.unknown);
      expect(RoomErrorCode.fromError(''), RoomErrorCode.unknown);
    });

    test('every code carries friendly copy with no raw code leaking through', () {
      for (final value in RoomErrorCode.values) {
        expect(value.message, isNotEmpty);
        expect(value.message, isNot(contains(value.code)));
        expect(value.message, isNot(contains('_')));
      }
    });

    test('codes are unique and none is a substring of another', () {
      final codes = RoomErrorCode.values.map((v) => v.code).toList();
      expect(codes.toSet().length, codes.length);
      for (final a in codes) {
        for (final b in codes) {
          if (a == b) continue;
          expect(a.contains(b), isFalse, reason: '$a contains $b — fromError would mis-map');
        }
      }
    });

    test('declaration order puts unknown last, since fromError scans in order', () {
      expect(RoomErrorCode.values.last, RoomErrorCode.unknown);
    });
  });

  group('tier-shaped room fields', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
      'id': 'r1',
      'code': 'ABCDEF',
      'name': 'Movie night',
      'created_by': 'u1',
      'created_at': '2026-08-04T12:00:00Z',
      'duration_minutes': 60,
      'expires_at': '2026-08-04T13:00:00Z',
      ...extra,
    };

    test('a row without the tier columns reads as a free-shaped room', () {
      final room = Room.fromJson(row(const {}));
      expect(room.persistent, isFalse);
      expect(room.avLevel, AvLevel.none);
      expect(room.maxMembers, 8);
      expect(room.mediaPosition, isNull);
    });

    test('the tier columns round-trip', () {
      final room = Room.fromJson(
        row(const {
          'persistent': true,
          'dormant_hours': 24,
          'av_level': 'video',
          'max_members': 16,
          'media_position_ms': 90000,
          'media_position_at': '2026-08-04T12:30:00Z',
          'resumable_until': '2026-08-05T13:00:00Z',
        }),
      );
      expect(room.persistent, isTrue);
      expect(room.avLevel, AvLevel.video);
      expect(room.maxMembers, 16);
      expect(room.mediaPosition, const Duration(seconds: 90));
      expect(room.resumableUntil, isNotNull);
      expect(room.goesDormant, isTrue);
    });

    test('a room with no dormancy and no persistence simply ends', () {
      final room = Room.fromJson(row(const {'dormant_hours': 0, 'persistent': false}));
      expect(room.goesDormant, isFalse);
    });

    test('av levels widen in order', () {
      expect(AvLevel.none.allowsVoice, isFalse);
      expect(AvLevel.none.allowsVideo, isFalse);
      expect(AvLevel.voice.allowsVoice, isTrue);
      expect(AvLevel.voice.allowsVideo, isFalse);
      expect(AvLevel.video.allowsVoice, isTrue);
      expect(AvLevel.video.allowsVideo, isTrue);
    });

    test('an unknown av level degrades to none rather than granting anything', () {
      expect(AvLevel.fromWire('ultra'), AvLevel.none);
      expect(AvLevel.fromWire(null), AvLevel.none);
    });

    test('an unknown state degrades to expired rather than looking usable', () {
      expect(RoomState.fromWire('live'), RoomState.live);
      expect(RoomState.fromWire('dormant'), RoomState.dormant);
      expect(RoomState.fromWire('who knows'), RoomState.expired);
      expect(RoomState.fromWire(null), RoomState.expired);
    });

    test('a listing row carries the caller standing alongside the room', () {
      final entry = MyRoom.fromJson(
        row(const {'state': 'dormant', 'role': 'host', 'member_count': 3, 'is_owner': true}),
      );
      expect(entry.room.name, 'Movie night');
      expect(entry.isDormant, isTrue);
      expect(entry.isLive, isFalse);
      expect(entry.isHost, isTrue);
      expect(entry.isOwner, isTrue);
      expect(entry.memberCount, 3);
    });

    test('an acting host is not the owner, so deletion stays with the creator', () {
      final entry = MyRoom.fromJson(
        row(const {'state': 'live', 'role': 'host', 'member_count': 2, 'is_owner': false}),
      );
      expect(entry.isHost, isTrue);
      expect(entry.isOwner, isFalse);
    });

    test('ownership is never assumed when the server did not say so', () {
      final entry = MyRoom.fromJson(row(const {'state': 'live', 'role': 'host'}));
      expect(entry.isOwner, isFalse);
    });
  });

  group('RoomExitEdge', () {
    test('fires once when the room is left', () {
      final edge = RoomExitEdge(true);
      expect(edge.observe(inRoom: false), isTrue);
      expect(edge.observe(inRoom: false), isFalse);
    });

    test('does not fire on entry, or while staying put', () {
      final edge = RoomExitEdge(false);
      expect(edge.observe(inRoom: true), isFalse);
      expect(edge.observe(inRoom: true), isFalse);
      expect(edge.observe(inRoom: false), isTrue);
    });

    test('fires again on a later exit', () {
      final edge = RoomExitEdge(true);
      expect(edge.observe(inRoom: false), isTrue);
      expect(edge.observe(inRoom: true), isFalse);
      expect(edge.observe(inRoom: false), isTrue);
    });

    test('a reaction that re-observes synchronously terminates', () {
      final edge = RoomExitEdge(true);
      var fired = 0;
      void react() {
        fired++;
        if (fired > 20) return;
        if (edge.observe(inRoom: false)) react();
      }

      if (edge.observe(inRoom: false)) react();
      expect(fired, 1);
    });
  });
}
