import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/sync/sync_events.dart';

typedef Revive = SyncEvent Function(Map<String, dynamic>);

class _Case {
  const _Case(this.event, this.revive, this.keys);

  final SyncEvent event;
  final Revive revive;
  final Set<String> keys;
}

const _base = {'senderId', 'timestamp'};

final _cases = <String, _Case>{
  'play (human)': _Case(
    const PlayEvent(senderId: 'u1', timestamp: 10),
    PlayEvent.fromPayload,
    {..._base, 'reason', 'subjectUserId'},
  ),
  'play (gate)': _Case(
    const PlayEvent(
      senderId: 'u1',
      timestamp: 10,
      reason: SyncActionReason.gate,
      subjectUserId: 'u2',
    ),
    PlayEvent.fromPayload,
    {..._base, 'reason', 'subjectUserId'},
  ),
  'pause (human)': _Case(
    const PauseEvent(senderId: 'u1', timestamp: 11),
    PauseEvent.fromPayload,
    {..._base, 'reason', 'subjectUserId'},
  ),
  'pause (gate)': _Case(
    const PauseEvent(
      senderId: 'u1',
      timestamp: 11,
      reason: SyncActionReason.gate,
      subjectUserId: 'u2',
    ),
    PauseEvent.fromPayload,
    {..._base, 'reason', 'subjectUserId'},
  ),
  'seek (human)': _Case(
    const SeekEvent(senderId: 'u1', timestamp: 12, positionMs: 4500),
    SeekEvent.fromPayload,
    {..._base, 'positionMs', 'reason'},
  ),
  'seek (transport)': _Case(
    const SeekEvent(
      senderId: 'u1',
      timestamp: 12,
      positionMs: 4500,
      reason: SyncActionReason.transport,
    ),
    SeekEvent.fromPayload,
    {..._base, 'positionMs', 'reason'},
  ),
  'seek (gate)': _Case(
    const SeekEvent(
      senderId: 'u1',
      timestamp: 12,
      positionMs: 0,
      reason: SyncActionReason.gate,
    ),
    SeekEvent.fromPayload,
    {..._base, 'positionMs', 'reason'},
  ),
  'state_request': _Case(
    const StateRequestEvent(senderId: 'u1', timestamp: 13),
    StateRequestEvent.fromPayload,
    _base,
  ),
  'state_response (local, full)': _Case(
    const StateResponseEvent(
      senderId: 'u1',
      timestamp: 14,
      playing: true,
      positionMs: 9000,
      mode: 'local',
      fileName: 'movie.mkv',
      fileDurationMs: 7200000,
    ),
    StateResponseEvent.fromPayload,
    {..._base, 'playing', 'positionMs', 'mode', 'youtubeUrl', 'fileName', 'fileDurationMs'},
  ),
  'state_response (youtube)': _Case(
    const StateResponseEvent(
      senderId: 'u1',
      timestamp: 14,
      playing: false,
      positionMs: 0,
      mode: 'youtube',
      youtubeUrl: 'https://youtu.be/abc',
    ),
    StateResponseEvent.fromPayload,
    {..._base, 'playing', 'positionMs', 'mode', 'youtubeUrl', 'fileName', 'fileDurationMs'},
  ),
  'mode_switch (local)': _Case(
    const ModeSwitchEvent(senderId: 'u1', timestamp: 15, mode: 'local'),
    ModeSwitchEvent.fromPayload,
    {..._base, 'mode', 'youtubeUrl'},
  ),
  'mode_switch (youtube)': _Case(
    const ModeSwitchEvent(
      senderId: 'u1',
      timestamp: 15,
      mode: 'youtube',
      youtubeUrl: 'https://youtu.be/abc',
    ),
    ModeSwitchEvent.fromPayload,
    {..._base, 'mode', 'youtubeUrl'},
  ),
  'chat': _Case(
    const ChatEvent(
      senderId: 'u1',
      timestamp: 16,
      displayName: 'Ada',
      message: 'hello there',
    ),
    ChatEvent.fromPayload,
    {..._base, 'displayName', 'message'},
  ),
  'typing (start)': _Case(
    const TypingEvent(senderId: 'u1', timestamp: 17, displayName: 'Ada', isTyping: true),
    TypingEvent.fromPayload,
    {..._base, 'displayName', 'isTyping'},
  ),
  'typing (stop)': _Case(
    const TypingEvent(senderId: 'u1', timestamp: 17, displayName: 'Ada', isTyping: false),
    TypingEvent.fromPayload,
    {..._base, 'displayName', 'isTyping'},
  ),
  'position_sync': _Case(
    const PositionSyncEvent(senderId: 'u1', timestamp: 18, positionMs: 30000, playing: true),
    PositionSyncEvent.fromPayload,
    {..._base, 'positionMs', 'playing'},
  ),
  'media_set (local)': _Case(
    const MediaSetEvent(
      senderId: 'u1',
      timestamp: 19,
      kind: 'local',
      name: 'movie.mkv',
      durationMs: 7200000,
      updatedAtMs: 1700000000000,
    ),
    MediaSetEvent.fromPayload,
    {..._base, 'kind', 'name', 'durationMs', 'url', 'updatedAtMs'},
  ),
  'media_set (youtube)': _Case(
    const MediaSetEvent(
      senderId: 'u1',
      timestamp: 19,
      kind: 'youtube',
      url: 'https://youtu.be/abc',
      updatedAtMs: 1700000000000,
    ),
    MediaSetEvent.fromPayload,
    {..._base, 'kind', 'name', 'durationMs', 'url', 'updatedAtMs'},
  ),
  'media_set (none)': _Case(
    const MediaSetEvent(senderId: 'u1', timestamp: 19, kind: 'none'),
    MediaSetEvent.fromPayload,
    {..._base, 'kind', 'name', 'durationMs', 'url', 'updatedAtMs'},
  ),
  'reaction': _Case(
    const ReactionEvent(senderId: 'u1', timestamp: 20, emoji: '👏', displayName: 'Ada'),
    ReactionEvent.fromPayload,
    {..._base, 'emoji', 'displayName'},
  ),
  'file_info': _Case(
    const FileInfoEvent(
      senderId: 'u1',
      timestamp: 21,
      fileName: 'movie.mkv',
      durationMs: 7200000,
    ),
    FileInfoEvent.fromPayload,
    {..._base, 'fileName', 'durationMs'},
  ),
};

void main() {
  group('wire round-trip', () {
    _cases.forEach((name, testCase) {
      test('$name survives serialize -> fromPayload -> serialize', () {
        final payload = testCase.event.toPayload();
        final revived = testCase.revive(payload);
        expect(revived.toPayload(), payload);
        expect(revived.senderId, testCase.event.senderId);
        expect(revived.timestamp, testCase.event.timestamp);
        expect(revived.runtimeType, testCase.event.runtimeType);
      });

      test('$name pins its exact wire keys', () {
        expect(testCase.event.toPayload().keys.toSet(), testCase.keys);
      });
    });
  });

  group('event type constants', () {
    test('are the strings the channel subscribes on', () {
      expect(SyncEventType.play, 'play');
      expect(SyncEventType.pause, 'pause');
      expect(SyncEventType.seek, 'seek');
      expect(SyncEventType.stateRequest, 'state_request');
      expect(SyncEventType.stateResponse, 'state_response');
      expect(SyncEventType.modeSwitch, 'mode_switch');
      expect(SyncEventType.chat, 'chat');
      expect(SyncEventType.typing, 'typing');
      expect(SyncEventType.positionSync, 'position_sync');
      expect(SyncEventType.fileInfo, 'file_info');
      expect(SyncEventType.mediaSet, 'media_set');
      expect(SyncEventType.memberKicked, 'member_kicked');
      expect(SyncEventType.transportLock, 'transport_lock');
      expect(SyncEventType.reaction, 'reaction');
      expect(SyncEventType.roomEnded, 'room_ended');
    });

    test('action reasons are the strings the gate and transport stamp', () {
      expect(SyncActionReason.gate, 'gate');
      expect(SyncActionReason.transport, 'transport');
    });
  });

  group('field decoding', () {
    test('play carries reason and subject through unchanged', () {
      final event = PlayEvent.fromPayload({
        'senderId': 'u1',
        'timestamp': 5,
        'reason': SyncActionReason.gate,
        'subjectUserId': 'u9',
      });
      expect(event.reason, SyncActionReason.gate);
      expect(event.subjectUserId, 'u9');
    });

    test('a human play has a null reason', () {
      final event = PlayEvent.fromPayload({'senderId': 'u1', 'timestamp': 5});
      expect(event.reason, isNull);
      expect(event.subjectUserId, isNull);
    });

    test('state_response defaults a missing mode to local', () {
      final event = StateResponseEvent.fromPayload({
        'senderId': 'u1',
        'timestamp': 5,
        'playing': true,
        'positionMs': 100,
      });
      expect(event.mode, 'local');
    });

    test('media_set keeps updatedAtMs as the server-clock ordering key', () {
      final event = MediaSetEvent.fromPayload({
        'senderId': 'u1',
        'timestamp': 5,
        'kind': 'local',
        'name': 'a.mkv',
        'updatedAtMs': 1700000000000,
      });
      expect(event.updatedAtMs, 1700000000000);
      expect(event.timestamp, isNot(event.updatedAtMs));
    });
  });

  group('malformed payload tolerance', () {
    test('media_set survives a completely empty payload', () {
      final event = MediaSetEvent.fromPayload({});
      expect(event.senderId, '');
      expect(event.timestamp, 0);
      expect(event.kind, 'none');
      expect(event.name, isNull);
      expect(event.durationMs, isNull);
      expect(event.url, isNull);
      expect(event.updatedAtMs, isNull);
    });

    test('media_set survives a null-valued payload', () {
      final event = MediaSetEvent.fromPayload({
        'senderId': null,
        'timestamp': null,
        'kind': null,
        'name': null,
      });
      expect(event.senderId, '');
      expect(event.timestamp, 0);
      expect(event.kind, 'none');
    });

    test('reaction survives an empty payload and names the sender Watcher', () {
      final event = ReactionEvent.fromPayload({});
      expect(event.senderId, '');
      expect(event.timestamp, 0);
      expect(event.emoji, '');
      expect(event.displayName, 'Watcher');
    });

    test('reaction with an unbundled emoji still decodes, for the allow-list to reject', () {
      final event = ReactionEvent.fromPayload({
        'senderId': 'u1',
        'timestamp': 5,
        'emoji': '🦆',
        'displayName': 'Ada',
      });
      expect(event.emoji, '🦆');
    });

    test('strict events throw on a missing senderId rather than inventing one', () {
      expect(() => PlayEvent.fromPayload({'timestamp': 5}), throwsA(isA<TypeError>()));
      expect(() => PauseEvent.fromPayload({'timestamp': 5}), throwsA(isA<TypeError>()));
      expect(
        () => SeekEvent.fromPayload({'timestamp': 5, 'positionMs': 0}),
        throwsA(isA<TypeError>()),
      );
      expect(() => StateRequestEvent.fromPayload({'timestamp': 5}), throwsA(isA<TypeError>()));
      expect(
        () => ChatEvent.fromPayload({'timestamp': 5, 'displayName': 'A', 'message': 'm'}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => TypingEvent.fromPayload({'timestamp': 5, 'displayName': 'A', 'isTyping': true}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => PositionSyncEvent.fromPayload({'timestamp': 5, 'positionMs': 0, 'playing': true}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => FileInfoEvent.fromPayload({'timestamp': 5, 'fileName': 'a', 'durationMs': 0}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => ModeSwitchEvent.fromPayload({'timestamp': 5, 'mode': 'local'}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => StateResponseEvent.fromPayload({'timestamp': 5, 'playing': true, 'positionMs': 0}),
        throwsA(isA<TypeError>()),
      );
    });

    test('strict events throw on a missing required body field', () {
      expect(
        () => SeekEvent.fromPayload({'senderId': 'u1', 'timestamp': 5}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => ChatEvent.fromPayload({'senderId': 'u1', 'timestamp': 5, 'displayName': 'A'}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => FileInfoEvent.fromPayload({'senderId': 'u1', 'timestamp': 5, 'fileName': 'a'}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => PositionSyncEvent.fromPayload({
          'senderId': 'u1',
          'timestamp': 5,
          'positionMs': 0,
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('strict events throw when a number arrives as a double', () {
      expect(
        () => SeekEvent.fromPayload({'senderId': 'u1', 'timestamp': 5, 'positionMs': 4500.0}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => PlayEvent.fromPayload({'senderId': 'u1', 'timestamp': 5.0}),
        throwsA(isA<TypeError>()),
      );
    });

    test('strict events throw when a field arrives with the wrong type', () {
      expect(
        () => TypingEvent.fromPayload({
          'senderId': 'u1',
          'timestamp': 5,
          'displayName': 'A',
          'isTyping': 'yes',
        }),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => ChatEvent.fromPayload({
          'senderId': 42,
          'timestamp': 5,
          'displayName': 'A',
          'message': 'm',
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('tolerant events are null-tolerant but not type-tolerant', () {
      expect(
        () => MediaSetEvent.fromPayload({'senderId': 'u1', 'timestamp': 5, 'kind': 7}),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => MediaSetEvent.fromPayload({
          'senderId': 'u1',
          'timestamp': 5,
          'kind': 'local',
          'durationMs': 'long',
        }),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => ReactionEvent.fromPayload({'senderId': 'u1', 'timestamp': 5, 'emoji': 7}),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
