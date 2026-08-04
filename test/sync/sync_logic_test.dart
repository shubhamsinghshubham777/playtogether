import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/sync/sync_logic.dart';

final _epoch = DateTime.utc(2026, 7, 31, 12);

PresentMember _member(
  String userId, {
  String role = 'member',
  int joinedSeconds = 0,
  ReadyStatus ready = ReadyStatus.none,
  String? file,
}) => PresentMember(
  userId: userId,
  displayName: userId,
  role: role,
  joinedAt: _epoch.add(Duration(seconds: joinedSeconds)),
  readyStatus: ready,
  loadedFileName: file,
);

const _localMedia = RoomMedia(kind: RoomMediaKind.local, name: 'movie.mkv');
const _ytMedia = RoomMedia(kind: RoomMediaKind.youtube, url: 'https://youtu.be/abc');

class _FakeClock {
  _FakeClock(this.now);
  DateTime now;
  DateTime call() => now;
}

class _FakeTimer implements Timer {
  _FakeTimer(this.due, this.callback);

  final DateTime due;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  void cancel() => cancelled = true;

  @override
  int get tick => fired ? 1 : 0;

  void fire() {
    fired = true;
    callback();
  }
}

class _FakeScheduler {
  _FakeScheduler(this.clock);

  final _FakeClock clock;
  final pending = <_FakeTimer>[];

  Timer schedule(Duration delay, void Function() callback) {
    final timer = _FakeTimer(clock.now.add(delay), callback);
    pending.add(timer);
    return timer;
  }

  void advance(Duration by) {
    final target = clock.now.add(by);
    clock.now = target;
    for (final timer in [...pending]) {
      if (timer.isActive && !timer.due.isAfter(target)) {
        pending.remove(timer);
        timer.fire();
      }
    }
  }
}

void main() {
  group('B1 authority election', () {
    test('nobody present elects nobody', () {
      expect(authorityAmong(const []), isNull);
    });

    test('the host wins even when they joined last', () {
      final elected = authorityAmong([
        _member('a', joinedSeconds: 0),
        _member('b', joinedSeconds: 10),
        _member('host', role: 'host', joinedSeconds: 99),
      ]);
      expect(elected, 'host');
    });

    test('with no host the earliest joiner wins', () {
      final elected = authorityAmong([
        _member('late', joinedSeconds: 50),
        _member('early', joinedSeconds: 1),
        _member('middle', joinedSeconds: 20),
      ]);
      expect(elected, 'early');
    });

    test('a joined_at tie breaks on the lower user id, so every client agrees', () {
      final elected = authorityAmong([
        _member('zoe', joinedSeconds: 5),
        _member('abe', joinedSeconds: 5),
        _member('mia', joinedSeconds: 5),
      ]);
      expect(elected, 'abe');
    });

    test('the election does not depend on candidate order', () {
      final members = [
        _member('zoe', joinedSeconds: 5),
        _member('abe', joinedSeconds: 5),
        _member('early', joinedSeconds: 1),
      ];
      expect(authorityAmong(members), 'early');
      expect(authorityAmong(members.reversed), 'early');
    });

    test('a sole member elects themselves', () {
      expect(authorityAmong([_member('solo')]), 'solo');
    });

    test('two hosts mid-succession resolve to the first one seen', () {
      final elected = authorityAmong([
        _member('old', role: 'host', joinedSeconds: 0),
        _member('new', role: 'host', joinedSeconds: 10),
      ]);
      expect(elected, 'old');
    });

    group('requester-excluded election', () {
      final room = [
        _member('host', role: 'host', joinedSeconds: 0),
        _member('early', joinedSeconds: 5),
        _member('late', joinedSeconds: 10),
      ];

      String? responderFor(String requesterId) =>
          authorityAmong(room.where((m) => m.userId != requesterId));

      test('a member asking is answered by the host', () {
        expect(responderFor('late'), 'host');
      });

      test('the host asking is answered by the next in line, not themselves', () {
        expect(responderFor('host'), 'early');
        expect(responderFor('host'), isNot('host'));
      });

      test('there is exactly one responder whoever asks', () {
        for (final requester in room) {
          final responders = room
              .where((m) => m.userId != requester.userId)
              .where((m) => responderFor(requester.userId) == m.userId);
          expect(responders.length, 1, reason: 'requester ${requester.userId}');
        }
      });

      test('a sole member asking gets no responder at all', () {
        final solo = [_member('solo', role: 'host')];
        expect(authorityAmong(solo.where((m) => m.userId != 'solo')), isNull);
      });
    });
  });

  group('B2 last-action-wins ordering', () {
    test('stamps strictly increase even within a single millisecond', () {
      final clock = _FakeClock(_epoch);
      final ordering = SyncOrdering(userId: 'me', now: clock.call);

      final stamps = List.generate(5, (_) => ordering.nextTimestamp());
      expect(stamps, [
        _epoch.millisecondsSinceEpoch,
        _epoch.millisecondsSinceEpoch + 1,
        _epoch.millisecondsSinceEpoch + 2,
        _epoch.millisecondsSinceEpoch + 3,
        _epoch.millisecondsSinceEpoch + 4,
      ]);
    });

    test('a play and a seek stamped in one synchronous block both survive', () {
      final clock = _FakeClock(_epoch);
      final sender = SyncOrdering(userId: 'sender', now: clock.call);
      final receiver = SyncOrdering(userId: 'me', now: clock.call);

      final play = {'senderId': 'sender', 'timestamp': sender.nextTimestamp()};
      final seek = {'senderId': 'sender', 'timestamp': sender.nextTimestamp()};

      expect(play['timestamp'], isNot(seek['timestamp']));
      expect(receiver.shouldApply(play), isTrue);
      expect(receiver.shouldApply(seek), isTrue);
    });

    test('the wall clock reasserts itself once it passes the issued stamp', () {
      final clock = _FakeClock(_epoch);
      final ordering = SyncOrdering(userId: 'me', now: clock.call);

      ordering.nextTimestamp();
      ordering.nextTimestamp();
      clock.now = _epoch.add(const Duration(seconds: 1));
      expect(ordering.nextTimestamp(), clock.now.millisecondsSinceEpoch);
    });

    test('a stamp equal to the last applied is dropped', () {
      final ordering = SyncOrdering(userId: 'me');
      expect(ordering.shouldApply({'senderId': 'other', 'timestamp': 100}), isTrue);
      expect(ordering.shouldApply({'senderId': 'other', 'timestamp': 100}), isFalse);
    });

    test('an older stamp is dropped, so a late-arriving event never wins', () {
      final ordering = SyncOrdering(userId: 'me');
      expect(ordering.shouldApply({'senderId': 'other', 'timestamp': 100}), isTrue);
      expect(ordering.shouldApply({'senderId': 'other', 'timestamp': 99}), isFalse);
      expect(ordering.shouldApply({'senderId': 'other', 'timestamp': 101}), isTrue);
    });

    test('own events are dropped even though the channel is self:false', () {
      final ordering = SyncOrdering(userId: 'me');
      expect(ordering.shouldApply({'senderId': 'me', 'timestamp': 100}), isFalse);
    });

    test('a dropped own event does not advance the applied watermark', () {
      final ordering = SyncOrdering(userId: 'me');
      ordering.shouldApply({'senderId': 'me', 'timestamp': 500});
      expect(ordering.lastApplied, 0);
      expect(ordering.shouldApply({'senderId': 'other', 'timestamp': 100}), isTrue);
    });

    test('a dropped stale event does not rewind the applied watermark', () {
      final ordering = SyncOrdering(userId: 'me');
      ordering.shouldApply({'senderId': 'other', 'timestamp': 100});
      ordering.shouldApply({'senderId': 'other', 'timestamp': 50});
      expect(ordering.lastApplied, 100);
    });

    test('ordering is global, not per sender', () {
      final ordering = SyncOrdering(userId: 'me');
      expect(ordering.shouldApply({'senderId': 'a', 'timestamp': 100}), isTrue);
      expect(ordering.shouldApply({'senderId': 'b', 'timestamp': 99}), isFalse);
      expect(ordering.shouldApply({'senderId': 'b', 'timestamp': 101}), isTrue);
    });
  });

  group('B3 gate evaluation', () {
    group('memberSatisfiesGate', () {
      test('a member who is not ready never satisfies it', () {
        for (final status in ReadyStatus.values) {
          final member = _member('a', ready: status, file: 'movie.mkv');
          expect(
            memberSatisfiesGate(member, _localMedia),
            status == ReadyStatus.ready,
            reason: status.name,
          );
        }
      });

      test('ready with the right file satisfies it', () {
        final member = _member('a', ready: .ready, file: 'movie.mkv');
        expect(memberSatisfiesGate(member, _localMedia), isTrue);
      });

      test('ready with the wrong file does not — ready means open, not correct', () {
        final member = _member('a', ready: .ready, file: 'weird.mp4');
        expect(memberSatisfiesGate(member, _localMedia), isFalse);
      });

      test('the file comparison is exact, not case- or whitespace-insensitive', () {
        expect(
          memberSatisfiesGate(_member('a', ready: .ready, file: 'Movie.mkv'), _localMedia),
          isFalse,
        );
        expect(
          memberSatisfiesGate(_member('a', ready: .ready, file: 'movie.mkv '), _localMedia),
          isFalse,
        );
      });

      test('ready with no file at all does not satisfy local media', () {
        expect(memberSatisfiesGate(_member('a', ready: .ready), _localMedia), isFalse);
      });

      test('youtube media ignores the loaded file name entirely', () {
        expect(memberSatisfiesGate(_member('a', ready: .ready), _ytMedia), isTrue);
        expect(
          memberSatisfiesGate(_member('a', ready: .ready, file: 'anything.mkv'), _ytMedia),
          isTrue,
        );
      });
    });

    group('gateState', () {
      test('is indeterminate before the first presence sync, never closed', () {
        final state = evaluateGateState(
          hasPresenceSynced: false,
          media: RoomMedia.none,
          members: const [],
        );
        expect(state, GateState.indeterminate);
        expect(state, isNot(GateState.closed));
      });

      test('stays indeterminate pre-sync even with media and members known', () {
        expect(
          evaluateGateState(
            hasPresenceSynced: false,
            media: _localMedia,
            members: [_member('a', ready: .ready, file: 'movie.mkv')],
          ),
          GateState.indeterminate,
        );
      });

      test('is closed when the room has no canonical media', () {
        expect(
          evaluateGateState(
            hasPresenceSynced: true,
            media: RoomMedia.none,
            members: [_member('a', ready: .ready)],
          ),
          GateState.closed,
        );
      });

      test('is indeterminate when presence synced but nobody is listed yet', () {
        expect(
          evaluateGateState(hasPresenceSynced: true, media: _localMedia, members: const []),
          GateState.indeterminate,
        );
      });

      test('is open when every member has the canonical media', () {
        expect(
          evaluateGateState(
            hasPresenceSynced: true,
            media: _localMedia,
            members: [
              _member('a', ready: .ready, file: 'movie.mkv'),
              _member('b', ready: .ready, file: 'movie.mkv'),
            ],
          ),
          GateState.open,
        );
      });

      test('one member short closes it for everyone', () {
        expect(
          evaluateGateState(
            hasPresenceSynced: true,
            media: _localMedia,
            members: [
              _member('a', ready: .ready, file: 'movie.mkv'),
              _member('b', ready: .loading),
            ],
          ),
          GateState.closed,
        );
      });

      test('one member on the wrong file closes it too', () {
        expect(
          evaluateGateState(
            hasPresenceSynced: true,
            media: _localMedia,
            members: [
              _member('a', ready: .ready, file: 'movie.mkv'),
              _member('b', ready: .ready, file: 'other.mkv'),
            ],
          ),
          GateState.closed,
        );
      });
    });

    group('gateBlockers', () {
      test('lists only the members not satisfying the gate', () {
        final blockers = gateBlockersOf(_localMedia, [
          _member('ok', ready: .ready, file: 'movie.mkv'),
          _member('loading', ready: .loading),
          _member('wrong', ready: .ready, file: 'other.mkv'),
        ]);
        expect(blockers.map((m) => m.userId), ['loading', 'wrong']);
      });

      test('is empty when everyone is satisfied', () {
        expect(
          gateBlockersOf(_localMedia, [_member('ok', ready: .ready, file: 'movie.mkv')]),
          isEmpty,
        );
      });

      test('is empty when no media is set, since there is nothing to be behind on', () {
        expect(gateBlockersOf(RoomMedia.none, [_member('a'), _member('b')]), isEmpty);
      });
    });

    group('gate transitions', () {
      GateTransition? transition({
        required GateState previous,
        required GateState next,
        bool isAuthority = true,
        bool roomPlaying = true,
        bool pausedByGate = false,
      }) => gateTransitionFor(
        previous: previous,
        next: next,
        isAuthority: isAuthority,
        roomPlaying: roomPlaying,
        pausedByGate: pausedByGate,
      );

      test('open -> closed while the room plays pauses it', () {
        expect(transition(previous: .open, next: .closed), GateTransition.pause);
      });

      test('the pause decision reads the room, not our own player', () {
        expect(transition(previous: .open, next: .closed, roomPlaying: false), isNull);
        expect(transition(previous: .open, next: .closed, roomPlaying: true), GateTransition.pause);
      });

      test('closed -> open resumes only when the gate is what paused us', () {
        expect(
          transition(previous: .closed, next: .open, pausedByGate: true),
          GateTransition.resume,
        );
        expect(transition(previous: .closed, next: .open, pausedByGate: false), isNull);
      });

      test('a non-authority derives nothing, so the room gets one pause not eight', () {
        expect(transition(previous: .open, next: .closed, isAuthority: false), isNull);
        expect(
          transition(previous: .closed, next: .open, isAuthority: false, pausedByGate: true),
          isNull,
        );
      });

      test('transitions out of and into indeterminate derive nothing', () {
        for (final state in GateState.values) {
          expect(
            transition(previous: .indeterminate, next: state, pausedByGate: true),
            isNull,
            reason: 'indeterminate -> ${state.name}',
          );
          expect(
            transition(previous: state, next: .indeterminate, pausedByGate: true),
            isNull,
            reason: '${state.name} -> indeterminate',
          );
        }
      });

      test('a repeated state derives nothing', () {
        for (final state in GateState.values) {
          expect(
            transition(previous: state, next: state, pausedByGate: true),
            isNull,
            reason: state.name,
          );
        }
      });
    });

    group('held resume position', () {
      test('is dropped when we are the member being waited on', () {
        var asked = false;
        final held = gateHeldPosition(
          subjectUserId: 'me',
          userId: 'me',
          position: () {
            asked = true;
            return const Duration(seconds: 30);
          },
        );
        expect(held, isNull);
        expect(asked, isFalse, reason: 'our position is about some other file');
      });

      test('is our current position when someone else is the blocker', () {
        final held = gateHeldPosition(
          subjectUserId: 'them',
          userId: 'me',
          position: () => const Duration(seconds: 30),
        );
        expect(held, const Duration(seconds: 30));
      });

      test('is our current position when no blocker is named', () {
        final held = gateHeldPosition(
          subjectUserId: null,
          userId: 'me',
          position: () => const Duration(seconds: 30),
        );
        expect(held, const Duration(seconds: 30));
      });

      test('is null when we have no position to offer', () {
        expect(gateHeldPosition(subjectUserId: 'them', userId: 'me', position: () => null), isNull);
      });
    });
  });

  group('B4 presence merge', () {
    Map<String, dynamic> payload(
      String userId, {
      String? ready,
      String? file,
      String role = 'member',
      int joinedSeconds = 0,
      bool? privacy,
    }) => {
      'user_id': userId,
      'display_name': userId,
      'role': role,
      'joined_at': _epoch.add(Duration(seconds: joinedSeconds)).toIso8601String(),
      'ready_status': ready,
      'loaded_file_name': file,
      if (privacy != null) 'privacy_mode': privacy,
    };

    test('a user on two devices counts once', () {
      final merged = mergePresence([payload('a'), payload('a')]);
      expect(merged.length, 1);
      expect(merged.single.userId, 'a');
    });

    test('of a user\'s devices the most ready one wins', () {
      final merged = mergePresence([
        payload('a', ready: 'none'),
        payload('a', ready: 'ready', file: 'movie.mkv'),
        payload('a', ready: 'loading'),
      ]);
      expect(merged.single.readyStatus, ReadyStatus.ready);
      expect(merged.single.loadedFileName, 'movie.mkv');
    });

    test('the winner does not depend on device order', () {
      final ascending = mergePresence([
        payload('a', ready: 'none'),
        payload('a', ready: 'ready', file: 'movie.mkv'),
      ]);
      final descending = mergePresence([
        payload('a', ready: 'ready', file: 'movie.mkv'),
        payload('a', ready: 'none'),
      ]);
      expect(ascending.single.readyStatus, ReadyStatus.ready);
      expect(descending.single.readyStatus, ReadyStatus.ready);
    });

    test('ReadyStatus declaration order is the rank the merge uses', () {
      expect(ReadyStatus.values, [
        ReadyStatus.none,
        ReadyStatus.selecting,
        ReadyStatus.loading,
        ReadyStatus.ready,
      ]);
      for (var i = 0; i < ReadyStatus.values.length - 1; i++) {
        final lower = ReadyStatus.values[i];
        final higher = ReadyStatus.values[i + 1];
        final merged = mergePresence([
          payload('a', ready: higher.wire),
          payload('a', ready: lower.wire),
        ]);
        expect(merged.single.readyStatus, higher, reason: '$higher should outrank $lower');
      }
    });

    test('a second idle device cannot drag a ready user back below the gate', () {
      final merged = mergePresence([
        payload('a', ready: 'ready', file: 'movie.mkv'),
        payload('a', ready: 'none'),
      ]);
      expect(memberSatisfiesGate(merged.single, _localMedia), isTrue);
    });

    test('members come back sorted by join time', () {
      final merged = mergePresence([
        payload('late', joinedSeconds: 30),
        payload('early', joinedSeconds: 1),
        payload('middle', joinedSeconds: 10),
      ]);
      expect(merged.map((m) => m.userId), ['early', 'middle', 'late']);
    });

    test('a payload with no user_id is skipped rather than crashing the sync', () {
      final merged = mergePresence([
        {'display_name': 'ghost'},
        payload('a'),
      ]);
      expect(merged.map((m) => m.userId), ['a']);
    });

    test('missing fields fall back rather than throwing', () {
      final merged = mergePresence([
        {'user_id': 'a'},
      ], now: () => _epoch);
      final member = merged.single;
      expect(member.displayName, 'Watcher');
      expect(member.role, 'member');
      expect(member.isHost, isFalse);
      expect(member.readyStatus, ReadyStatus.none);
      expect(member.loadedFileName, isNull);
      expect(member.avatarUrl, isNull);
      expect(member.privacyMode, isFalse);
      expect(member.joinedAt, _epoch);
    });

    test('a client that predates privacy mode reads as not private', () {
      expect(mergePresence([payload('a')]).single.privacyMode, isFalse);
    });

    test('privacy survives the merge only when every device reports it', () {
      final all = mergePresence([payload('a', privacy: true), payload('a', privacy: true)]);
      expect(all.single.privacyMode, isTrue);

      final some = mergePresence([payload('a', privacy: true), payload('a', privacy: false)]);
      expect(some.single.privacyMode, isFalse);
    });

    test('a device that can still see the room outvotes the readiness winner', () {
      final merged = mergePresence([
        payload('a', ready: 'ready', file: 'movie.mkv', privacy: true),
        payload('a', ready: 'none', privacy: false),
      ]);
      expect(merged.single.readyStatus, ReadyStatus.ready);
      expect(merged.single.privacyMode, isFalse);
    });

    test('the merged privacy does not depend on device order', () {
      final ascending = mergePresence([
        payload('a', privacy: false),
        payload('a', ready: 'ready', privacy: true),
      ]);
      final descending = mergePresence([
        payload('a', ready: 'ready', privacy: true),
        payload('a', privacy: false),
      ]);
      expect(ascending.single.privacyMode, isFalse);
      expect(descending.single.privacyMode, isFalse);
    });

    test('an unparseable joined_at falls back to now rather than throwing', () {
      final merged = mergePresence([
        {'user_id': 'a', 'joined_at': 'not-a-date'},
      ], now: () => _epoch);
      expect(merged.single.joinedAt, _epoch);
    });

    test('an unknown ready_status reads as none and holds the gate shut', () {
      final merged = mergePresence([payload('a', ready: 'transcoding')]);
      expect(merged.single.readyStatus, ReadyStatus.none);
      expect(memberSatisfiesGate(merged.single, _localMedia), isFalse);
    });

    test('a client predating the gate sends no status and holds it shut', () {
      final merged = mergePresence([
        {'user_id': 'a', 'display_name': 'Old', 'role': 'member'},
      ], now: () => _epoch);
      expect(merged.single.readyStatus, ReadyStatus.none);
      expect(memberSatisfiesGate(merged.single, _localMedia), isFalse);
    });

    test('an empty presence state merges to nobody', () {
      expect(mergePresence(const []), isEmpty);
    });

    test('the merged list feeds authority election with the host preserved', () {
      final merged = mergePresence([
        payload('member', joinedSeconds: 1),
        payload('host', role: 'host', joinedSeconds: 50),
      ]);
      expect(authorityAmong(merged), 'host');
    });
  });

  group('C6 chat history merge after reconnect', () {
    ChatMessage message(String content, {String sender = 'u1', int seconds = 0}) => ChatMessage(
      senderId: sender,
      displayName: sender,
      content: content,
      sentAt: _epoch.add(Duration(seconds: seconds)),
    );

    test('history rows already held live are not duplicated', () {
      final live = [message('hello', seconds: 0)];
      mergeChatHistory(live, [message('hello', seconds: 0)]);
      expect(live, hasLength(1));
    });

    test('DB and sender clocks within the window are treated as the same message', () {
      final live = [message('hello', seconds: 0)];
      mergeChatHistory(live, [message('hello', seconds: 9)]);
      expect(live, hasLength(1));
    });

    test('the same text beyond the window is a genuinely separate message', () {
      final live = [message('hello', seconds: 0)];
      mergeChatHistory(live, [message('hello', seconds: 11)]);
      expect(live, hasLength(2));
    });

    test('clock skew in either direction is absorbed', () {
      final ahead = [message('hello', seconds: 9)];
      mergeChatHistory(ahead, [message('hello', seconds: 0)]);
      expect(ahead, hasLength(1));

      final behind = [message('hello', seconds: 0)];
      mergeChatHistory(behind, [message('hello', seconds: 9)]);
      expect(behind, hasLength(1));
    });

    test('the same text from different senders is never collapsed', () {
      final live = [message('hello', sender: 'u1')];
      mergeChatHistory(live, [message('hello', sender: 'u2')]);
      expect(live, hasLength(2));
    });

    test('different text from the same sender is never collapsed', () {
      final live = [message('hello')];
      mergeChatHistory(live, [message('goodbye')]);
      expect(live, hasLength(2));
    });

    test('messages missed while disconnected are added', () {
      final live = [message('before', seconds: 0)];
      mergeChatHistory(live, [
        message('before', seconds: 1),
        message('missed one', seconds: 30),
        message('missed two', seconds: 60),
      ]);
      expect(live.map((m) => m.content), ['before', 'missed one', 'missed two']);
    });

    test('the transcript comes back in send order', () {
      final live = [message('third', seconds: 30)];
      mergeChatHistory(live, [message('first', seconds: 0), message('second', seconds: 15)]);
      expect(live.map((m) => m.content), ['first', 'second', 'third']);
    });

    test('merging the same history twice is idempotent', () {
      final live = <ChatMessage>[];
      final history = [message('a', seconds: 0), message('b', seconds: 30)];
      mergeChatHistory(live, history);
      mergeChatHistory(live, history);
      expect(live, hasLength(2));
    });

    test('an empty history leaves the transcript untouched', () {
      final live = [message('hello')];
      mergeChatHistory(live, const []);
      expect(live, hasLength(1));
    });

    test('the merge window is the documented ten seconds', () {
      expect(kChatMergeWindow, const Duration(seconds: 10));
      expect(chatMessagesMatch(message('hi', seconds: 0), message('hi', seconds: 10)), isTrue);
      expect(chatMessagesMatch(message('hi', seconds: 0), message('hi', seconds: 11)), isFalse);
    });
  });

  group('B5 reaction send throttle', () {
    late _FakeClock clock;
    late _FakeScheduler scheduler;
    late ReactionThrottle throttle;
    late List<String> sent;

    setUp(() {
      clock = _FakeClock(_epoch);
      scheduler = _FakeScheduler(clock);
      throttle = ReactionThrottle(now: clock.call, schedule: scheduler.schedule);
      sent = [];
    });

    void submit(String emoji) => throttle.submit(emoji, sent.add);

    test('the first reaction goes out immediately', () {
      submit('👏');
      expect(sent, ['👏']);
    });

    test('a burst is coalesced rather than dropped, and the last emoji wins', () {
      submit('👏');
      submit('😂');
      submit('🎉');
      expect(sent, ['👏']);

      scheduler.advance(const Duration(milliseconds: 250));
      expect(sent, ['👏', '🎉']);
    });

    test('tapping two different emoji quickly does not lose the second', () {
      submit('👍');
      submit('💖');
      expect(sent, ['👍']);

      scheduler.advance(const Duration(milliseconds: 250));
      expect(sent, ['👍', '💖']);
    });

    test('a burst produces exactly one extra broadcast, not one per tap', () {
      submit('👏');
      for (var i = 0; i < 20; i++) {
        submit('😂');
      }
      scheduler.advance(const Duration(milliseconds: 250));
      expect(sent.length, 2);
    });

    test('the flush timer is not restarted by later taps in the same window', () {
      submit('👏');
      clock.now = clock.now.add(const Duration(milliseconds: 100));
      submit('😂');
      clock.now = clock.now.add(const Duration(milliseconds: 100));
      submit('🎉');
      expect(scheduler.pending.length, 1);

      scheduler.advance(const Duration(milliseconds: 50));
      expect(sent, ['👏', '🎉']);
    });

    test('reactions spaced beyond the interval each go out immediately', () {
      submit('👏');
      scheduler.advance(const Duration(milliseconds: 250));
      submit('😂');
      scheduler.advance(const Duration(milliseconds: 250));
      submit('🎉');
      expect(sent, ['👏', '😂', '🎉']);
      expect(scheduler.pending, isEmpty);
    });

    test('a reaction exactly on the interval boundary goes out immediately', () {
      submit('👏');
      clock.now = clock.now.add(const Duration(milliseconds: 250));
      submit('😂');
      expect(sent, ['👏', '😂']);
    });

    test('the window restarts from the flush, so back-to-back bursts stay capped', () {
      submit('👏');
      submit('😂');
      scheduler.advance(const Duration(milliseconds: 250));
      expect(sent, ['👏', '😂']);

      submit('🎉');
      expect(sent, ['👏', '😂']);
      scheduler.advance(const Duration(milliseconds: 250));
      expect(sent, ['👏', '😂', '🎉']);
    });

    test('disposing cancels a pending flush and drops later submissions', () {
      submit('👏');
      submit('😂');
      throttle.dispose();

      scheduler.advance(const Duration(milliseconds: 250));
      expect(sent, ['👏']);

      submit('🎉');
      expect(sent, ['👏']);
    });
  });

  group('resume decision', () {
    test('reopens the stored file when it still matches the room media', () {
      expect(
        shouldAutoReopenLocalFile(
          media: _localMedia,
          storedFileName: 'movie.mkv',
          storedFileExists: true,
          loadedFileName: null,
          isPickerOpen: false,
        ),
        isTrue,
      );
    });

    test('never reopens a file the room has moved off', () {
      expect(
        shouldAutoReopenLocalFile(
          media: _localMedia,
          storedFileName: 'other.mkv',
          storedFileExists: true,
          loadedFileName: null,
          isPickerOpen: false,
        ),
        isFalse,
      );
    });

    test('a path that no longer resolves is not reopened', () {
      expect(
        shouldAutoReopenLocalFile(
          media: _localMedia,
          storedFileName: 'movie.mkv',
          storedFileExists: false,
          loadedFileName: null,
          isPickerOpen: false,
        ),
        isFalse,
      );
    });

    test('does nothing when the right file is already open', () {
      expect(
        shouldAutoReopenLocalFile(
          media: _localMedia,
          storedFileName: 'movie.mkv',
          storedFileExists: true,
          loadedFileName: 'movie.mkv',
          isPickerOpen: false,
        ),
        isFalse,
      );
    });

    test('a picker that is open owns the choice', () {
      expect(
        shouldAutoReopenLocalFile(
          media: _localMedia,
          storedFileName: 'movie.mkv',
          storedFileExists: true,
          loadedFileName: null,
          isPickerOpen: true,
        ),
        isFalse,
      );
    });

    test('youtube rooms never consult the local path map', () {
      expect(
        shouldAutoReopenLocalFile(
          media: _ytMedia,
          storedFileName: 'movie.mkv',
          storedFileExists: true,
          loadedFileName: null,
          isPickerOpen: false,
        ),
        isFalse,
      );
    });

    test('resumes at the held position', () {
      expect(
        resumeSeekPosition(
          held: const Duration(minutes: 12),
          mediaDuration: const Duration(hours: 2),
        ),
        const Duration(minutes: 12),
      );
    });

    test('a position at the very start is not worth a seek', () {
      expect(resumeSeekPosition(held: Duration.zero, mediaDuration: null), isNull);
      expect(resumeSeekPosition(held: null, mediaDuration: null), isNull);
    });

    test('a position in the closing credits restarts instead', () {
      expect(
        resumeSeekPosition(
          held: const Duration(minutes: 119, seconds: 55),
          mediaDuration: const Duration(hours: 2),
        ),
        isNull,
      );
    });

    test('an unknown duration still resumes', () {
      expect(
        resumeSeekPosition(held: const Duration(minutes: 3), mediaDuration: null),
        const Duration(minutes: 3),
      );
    });
  });

  group('gate waiver', () {
    test('a waived member no longer holds the gate shut', () {
      final members = [
        _member('host', role: 'host', ready: ReadyStatus.ready, file: 'movie.mkv'),
        _member('slow'),
      ];
      expect(
        evaluateGateState(hasPresenceSynced: true, media: _localMedia, members: members),
        GateState.closed,
      );
      expect(
        evaluateGateState(
          hasPresenceSynced: true,
          media: _localMedia,
          members: members,
          waived: {'slow'},
        ),
        GateState.open,
      );
    });

    test('a waiver covers only the members it names', () {
      final members = [
        _member('host', role: 'host', ready: ReadyStatus.ready, file: 'movie.mkv'),
        _member('slow'),
        _member('later'),
      ];
      expect(
        evaluateGateState(
          hasPresenceSynced: true,
          media: _localMedia,
          members: members,
          waived: {'slow'},
        ),
        GateState.closed,
      );
    });

    test('waived members drop out of the blocker list the copy is built from', () {
      final members = [
        _member('host', role: 'host', ready: ReadyStatus.ready, file: 'movie.mkv'),
        _member('slow'),
        _member('later'),
      ];
      expect(gateBlockersOf(_localMedia, members, waived: {'slow'}).map((m) => m.userId), [
        'later',
      ]);
      expect(gateBlockersOf(_localMedia, members).map((m) => m.userId), ['slow', 'later']);
    });

    test('a waiver cannot conjure a gate out of no media', () {
      expect(
        evaluateGateState(
          hasPresenceSynced: true,
          media: RoomMedia.none,
          members: [_member('a')],
          waived: {'a'},
        ),
        GateState.closed,
      );
    });

    test('memberClearsGate still reports the underlying readiness truthfully', () {
      final slow = _member('slow');
      expect(memberSatisfiesGate(slow, _localMedia), isFalse);
      expect(memberClearsGate(slow, _localMedia, {'slow'}), isTrue);
      expect(memberClearsGate(slow, _localMedia, const {}), isFalse);
    });
  });

  group('B6 presence trailing throttle', () {
    late _FakeClock clock;
    late _FakeScheduler scheduler;
    late TrailingThrottle<Map<String, dynamic>> throttle;
    late List<Map<String, dynamic>> sent;

    setUp(() {
      clock = _FakeClock(_epoch);
      scheduler = _FakeScheduler(clock);
      throttle = TrailingThrottle<Map<String, dynamic>>(
        interval: const Duration(seconds: 2),
        maxCalls: 4,
        window: const Duration(seconds: 30),
        equals: presencePayloadsMatch,
        now: clock.call,
        schedule: scheduler.schedule,
      );
      sent = [];
    });

    Map<String, dynamic> state(String ready, {String? file}) => {
      'ready_status': ready,
      'loaded_file_name': file,
    };

    void submit(String ready, {String? file}) =>
        throttle.submit(state(ready, file: file), sent.add);

    void advance(Duration d) => scheduler.advance(d);

    test('a picker flip that nets to no change costs nothing', () {
      submit('none');
      expect(sent.length, 1);

      submit('selecting');
      advance(const Duration(milliseconds: 500));
      submit('none');
      advance(const Duration(seconds: 3));

      expect(sent.length, 1);
    });

    test('the real file-open flow stays inside the server budget', () {
      submit('none');
      submit('selecting');
      advance(const Duration(milliseconds: 400));
      submit('none');
      advance(const Duration(milliseconds: 900));
      submit('selecting');
      advance(const Duration(milliseconds: 600));
      submit('none');
      advance(const Duration(seconds: 3));
      submit('none', file: 'movie.mkv');
      advance(const Duration(seconds: 3));
      submit('ready', file: 'movie.mkv');
      advance(const Duration(seconds: 3));

      expect(sent.length, lessThanOrEqualTo(4));
      expect(sent.last['ready_status'], 'ready');
    });

    test('no 30-second window ever exceeds the server budget', () {
      final at = <int>[];
      void record(Map<String, dynamic> p) {
        sent.add(p);
        at.add(clock.now.millisecondsSinceEpoch);
      }

      for (var i = 0; i < 200; i++) {
        throttle.submit(state(i.isEven ? 'selecting' : 'none', file: 'f$i'), record);
        advance(const Duration(milliseconds: 500));
      }

      for (final start in at) {
        final inWindow = at.where((t) => t >= start && t - start < 30000).length;
        expect(inWindow, lessThanOrEqualTo(4));
      }
      expect(sent, isNotEmpty);
    });

    test('the budget frees up once the window rolls past', () {
      for (var i = 0; i < 8; i++) {
        submit('ready', file: 'f$i');
        advance(const Duration(seconds: 2));
      }
      expect(sent.length, 4);

      advance(const Duration(seconds: 30));
      expect(sent.last['loaded_file_name'], 'f7');
    });

    test('the final state always lands, even when deferred by the budget', () {
      for (var i = 0; i < 6; i++) {
        submit('selecting', file: 'f$i');
        advance(const Duration(seconds: 2));
      }
      submit('ready', file: 'final.mkv');
      advance(const Duration(seconds: 60));

      expect(sent.last['ready_status'], 'ready');
      expect(sent.last['loaded_file_name'], 'final.mkv');
      expect(throttle.hasPending, isFalse);
    });

    test('discardPending drops the superseded queue but keeps the budget', () {
      submit('none');
      submit('selecting');
      throttle.discardPending();
      submit('ready', file: 'movie.mkv');
      advance(const Duration(seconds: 3));

      expect(sent.length, 2);
      expect(sent.last['ready_status'], 'ready');
    });

    test('renew re-announces an unchanged state, since a new channel knows nothing', () {
      submit('ready', file: 'movie.mkv');
      expect(sent.length, 1);

      submit('ready', file: 'movie.mkv');
      advance(const Duration(seconds: 3));
      expect(sent.length, 1);

      throttle.renew();
      submit('ready', file: 'movie.mkv');
      advance(const Duration(seconds: 3));
      expect(sent.length, 2);
    });

    test('a disposed throttle stops writing', () {
      submit('none');
      submit('ready', file: 'movie.mkv');
      throttle.dispose();
      advance(const Duration(seconds: 30));
      expect(sent.length, 1);
    });
  });

  group('B6b presence payload equality', () {
    test('identical payloads match', () {
      expect(presencePayloadsMatch(const {'a': 1, 'b': null}, const {'a': 1, 'b': null}), isTrue);
    });

    test('a changed value does not match', () {
      expect(presencePayloadsMatch(const {'a': 1}, const {'a': 2}), isFalse);
    });

    test('a changed key does not match', () {
      expect(presencePayloadsMatch(const {'a': 1}, const {'b': 1}), isFalse);
    });

    test('a differing size does not match', () {
      expect(presencePayloadsMatch(const {'a': 1}, const {'a': 1, 'b': 2}), isFalse);
    });
  });

  group('B7 playable position', () {
    test('a negative position reported right after open reads as the start', () {
      expect(playablePosition(const Duration(milliseconds: -41)), Duration.zero);
    });

    test('a large negative still reads as the start', () {
      expect(playablePosition(const Duration(seconds: -30)), Duration.zero);
    });

    test('zero and real positions pass through untouched', () {
      expect(playablePosition(Duration.zero), Duration.zero);
      expect(playablePosition(const Duration(milliseconds: 1)), const Duration(milliseconds: 1));
      expect(playablePosition(const Duration(minutes: 42)), const Duration(minutes: 42));
    });

    test('a clamped position is one the room write accepts', () {
      expect(
        playablePosition(const Duration(milliseconds: -41)).inMilliseconds,
        greaterThanOrEqualTo(0),
      );
    });
  });
}
