import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/app_router.dart';

void main() {
  group('room path helpers', () {
    test('the prefix keeps rooms nested under the lobby', () {
      expect(kRoomPathPrefix, '/lobby/room/');
      expect(kRoomPathPrefix.startsWith('/lobby/'), isTrue);
    });

    test('roomPath and roomIdOfPath are inverses', () {
      const ids = [
        'r1',
        '550e8400-e29b-41d4-a716-446655440000',
        'ABC123',
        'a',
        '0',
        'id-with-dashes',
        'id_with_underscores',
        'id.with.dots',
      ];
      for (final id in ids) {
        expect(roomIdOfPath(roomPath(id)), id, reason: id);
      }
    });

    test('roomPath builds the nested location', () {
      expect(roomPath('r1'), '/lobby/room/r1');
    });

    test('non-room locations read as not-in-a-room', () {
      expect(roomIdOfPath('/lobby'), isNull);
      expect(roomIdOfPath('/login'), isNull);
      expect(roomIdOfPath('/lobby/profile'), isNull);
      expect(roomIdOfPath('/'), isNull);
      expect(roomIdOfPath(''), isNull);
      expect(roomIdOfPath('/room/r1'), isNull);
      expect(roomIdOfPath('lobby/room/r1'), isNull);
    });

    test('a prefix with no id reads as an empty id, not as null', () {
      expect(roomIdOfPath('/lobby/room/'), '');
    });

    test('ids containing odd characters survive the round trip verbatim', () {
      const odd = ['id with spaces', 'id/with/slashes', 'id?with=query', 'id#frag', 'ID%20enc'];
      for (final id in odd) {
        expect(roomIdOfPath(roomPath(id)), id, reason: id);
      }
    });

    test('a trailing segment stays part of the id rather than being split off', () {
      expect(roomIdOfPath('/lobby/room/r1/extra'), 'r1/extra');
    });
  });
}
