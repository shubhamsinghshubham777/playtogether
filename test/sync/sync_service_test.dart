import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/sync/sync_events.dart';
import 'package:playtogether/sync/sync_service.dart';

import 'fakes.dart';

const _me = 'me';
const _other = 'other';

class _Harness {
  _Harness({
    String userId = _me,
    String role = 'member',
    RoomMedia media = RoomMedia.none,
    int? joinedSeconds,
  }) {
    backend = FakeSyncBackend();
    if (joinedSeconds != null) {
      backend.membership = MembershipRow(role: role, joinedAt: presenceJoinedAt(joinedSeconds));
    }
    player = FakeSyncPlayer();
    service = SyncService(
      player,
      room: testRoom(media: media),
      profile: testProfile(userId),
      role: role,
      backend: backend,
    );
  }

  late final FakeSyncBackend backend;
  late final FakeSyncPlayer player;
  late final SyncService service;

  final remotePlays = <int>[];
  final remotePauses = <int>[];
  final remoteSeeks = <Duration>[];
  final driftCorrections = <Duration>[];
  final actions = <RemoteAction>[];
  final reactions = <ReactionEvent>[];
  final connectionEvents = <bool>[];

  FakeSyncChannel get channel => backend.channelInUse;

  void connect({bool routeToHooks = true, bool subscribed = true}) {
    if (routeToHooks) {
      service.onRemotePlay = () => remotePlays.add(1);
      service.onRemotePause = () => remotePauses.add(1);
      service.onRemoteSeek = remoteSeeks.add;
      service.onRemoteDriftCorrect = driftCorrections.add;
    }
    service.remoteActions.listen(actions.add);
    service.reactionsStream.listen(reactions.add);
    service.connectionStream.listen(connectionEvents.add);
    unawaited(service.loadMembership());
    service.connect();
    if (subscribed) channel.emitStatus(SyncSubscribeStatus.subscribed);
  }

  void dispose() => service.dispose();
}

void main() {
  group('C2 echo and loop prevention', () {
    test('a remote play is applied without being rebroadcast', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        h.channel.sent.clear();

        h.channel.deliver(SyncEventType.play, {'senderId': _other, 'timestamp': 100});
        async.flushMicrotasks();

        expect(h.remotePlays, hasLength(1));
        expect(h.channel.hasSent(SyncEventType.play), isFalse);
        h.dispose();
      });
    });

    test('a broadcast attempted while applying a remote action is suppressed', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        h.channel.sent.clear();

        h.channel.deliver(SyncEventType.play, {'senderId': _other, 'timestamp': 100});
        h.service.broadcastPlay();
        async.flushMicrotasks();
        expect(h.channel.hasSent(SyncEventType.play), isFalse);

        h.dispose();
      });
    });

    test('broadcasts re-arm once the 100ms settle window elapses', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        h.channel.sent.clear();

        h.channel.deliver(SyncEventType.play, {'senderId': _other, 'timestamp': 100});
        async.elapse(const Duration(milliseconds: 100));

        h.service.broadcastPlay();
        async.flushMicrotasks();
        expect(h.channel.hasSent(SyncEventType.play), isTrue);

        h.dispose();
      });
    });

    test('the settle window has not expired a millisecond early', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        h.channel.sent.clear();

        h.channel.deliver(SyncEventType.play, {'senderId': _other, 'timestamp': 100});
        async.elapse(const Duration(milliseconds: 99));

        h.service.broadcastPlay();
        async.flushMicrotasks();
        expect(h.channel.hasSent(SyncEventType.play), isFalse);

        h.dispose();
      });
    });

    test('our own event is ignored even if the channel echoes it back', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.play, {'senderId': _me, 'timestamp': 100});
        async.flushMicrotasks();

        expect(h.remotePlays, isEmpty);
        h.dispose();
      });
    });

    test('a stale timestamp is dropped rather than applied out of order', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.play, {'senderId': _other, 'timestamp': 200});
        async.elapse(const Duration(milliseconds: 100));
        h.channel.deliver(SyncEventType.pause, {'senderId': _other, 'timestamp': 150});
        async.elapse(const Duration(milliseconds: 100));

        expect(h.remotePlays, hasLength(1));
        expect(h.remotePauses, isEmpty);
        h.dispose();
      });
    });

    test('a malformed broadcast is swallowed and never kills the channel', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.seek, {'senderId': _other});
        h.channel.deliver(SyncEventType.play, {'timestamp': 'not-a-number'});
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.play, {'senderId': _other, 'timestamp': 300});
        async.flushMicrotasks();
        expect(h.remotePlays, hasLength(1));

        h.dispose();
      });
    });

    test('a payload nested one level down by the REST fallback still applies', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.play, {
          'payload': {'senderId': _other, 'timestamp': 100},
        });
        async.flushMicrotasks();

        expect(h.remotePlays, hasLength(1));
        h.dispose();
      });
    });
  });

  group('C3 late-joiner state sync', () {
    test('subscribing asks the room for its state', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        expect(h.channel.hasSent(SyncEventType.stateRequest), isTrue);
        h.dispose();
      });
    });

    test('an unanswered request is retried exactly once, after 2s', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        expect(h.channel.sentOf(SyncEventType.stateRequest), hasLength(1));

        async.elapse(const Duration(seconds: 2));
        expect(h.channel.sentOf(SyncEventType.stateRequest), hasLength(2));

        async.elapse(const Duration(seconds: 10));
        expect(h.channel.sentOf(SyncEventType.stateRequest), hasLength(2));

        h.dispose();
      });
    });

    test('a response arriving in the retry window is applied', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.stateResponse, {
          'senderId': _other,
          'timestamp': 100,
          'playing': true,
          'positionMs': 30000,
          'mode': 'local',
        });
        async.elapse(const Duration(milliseconds: 600));

        expect(h.remoteSeeks, [const Duration(seconds: 30)]);
        expect(h.remotePlays, hasLength(1));
        h.dispose();
      });
    });

    test('after the retry window the room is assumed idle and a late response ignored', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));

        h.channel.deliver(SyncEventType.stateResponse, {
          'senderId': _other,
          'timestamp': 100,
          'playing': true,
          'positionMs': 30000,
          'mode': 'local',
        });
        async.elapse(const Duration(seconds: 1));

        expect(h.remoteSeeks, isEmpty);
        h.dispose();
      });
    });

    test('the authority answers a state request', () {
      fakeAsync((async) {
        final h = _Harness(role: 'host')..connect();
        h.player.durationValue = const Duration(minutes: 90);
        h.channel.syncPresence([
          presenceEntry(_me, role: 'host', joinedSeconds: 0),
          presenceEntry(_other, joinedSeconds: 10),
        ]);
        async.flushMicrotasks();
        h.channel.sent.clear();

        h.channel.deliver(SyncEventType.stateRequest, {'senderId': _other, 'timestamp': 100});
        async.flushMicrotasks();

        expect(h.channel.hasSent(SyncEventType.stateResponse), isTrue);
        h.dispose();
      });
    });

    test('a non-authority stays quiet, so the joiner gets exactly one response', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        h.player.durationValue = const Duration(minutes: 90);
        h.channel.syncPresence([
          presenceEntry('host', role: 'host', joinedSeconds: 0),
          presenceEntry(_me, joinedSeconds: 10),
          presenceEntry('joiner', joinedSeconds: 20),
        ]);
        async.flushMicrotasks();
        h.channel.sent.clear();

        h.channel.deliver(SyncEventType.stateRequest, {'senderId': 'joiner', 'timestamp': 100});
        async.flushMicrotasks();

        expect(h.channel.hasSent(SyncEventType.stateResponse), isFalse);
        h.dispose();
      });
    });

    test('when the host asks, the next in line answers instead', () {
      fakeAsync((async) {
        final h = _Harness(joinedSeconds: 10)..connect();
        h.player.durationValue = const Duration(minutes: 90);
        h.channel.syncPresence([
          presenceEntry('host', role: 'host', joinedSeconds: 0),
          presenceEntry(_me, joinedSeconds: 10),
          presenceEntry('later', joinedSeconds: 20),
        ]);
        async.flushMicrotasks();
        h.channel.sent.clear();

        h.channel.deliver(SyncEventType.stateRequest, {'senderId': 'host', 'timestamp': 100});
        async.flushMicrotasks();

        expect(h.channel.hasSent(SyncEventType.stateResponse), isTrue);
        h.dispose();
      });
    });

    test('a member with nothing open never answers', () {
      fakeAsync((async) {
        final h = _Harness(role: 'host')..connect();
        h.channel.syncPresence([presenceEntry(_me, role: 'host')]);
        async.flushMicrotasks();
        h.channel.sent.clear();

        h.channel.deliver(SyncEventType.stateRequest, {'senderId': _other, 'timestamp': 100});
        async.flushMicrotasks();

        expect(h.channel.hasSent(SyncEventType.stateResponse), isFalse);
        h.dispose();
      });
    });

    test('alone in the room we do not re-ask on becoming gate-satisfied', () {
      fakeAsync((async) {
        final media = RoomMedia(
          kind: RoomMediaKind.local,
          name: 'movie.mkv',
          updatedAt: DateTime.utc(2026, 7, 31, 10, 30),
        );
        final h = _Harness(media: media)..connect();
        h.channel.syncPresence([presenceEntry(_me, ready: 'ready', file: 'movie.mkv')]);
        async.elapse(const Duration(seconds: 5));
        h.channel.sent.clear();

        h.service.retrackReadiness(ReadyStatus.ready, loadedFileName: 'movie.mkv');
        async.flushMicrotasks();

        expect(h.channel.hasSent(SyncEventType.stateRequest), isFalse);
        h.dispose();
      });
    });

    test('with others present we re-ask on first opening the room\'s media', () {
      fakeAsync((async) {
        final media = RoomMedia(
          kind: RoomMediaKind.local,
          name: 'movie.mkv',
          updatedAt: DateTime.utc(2026, 7, 31, 10, 30),
        );
        final h = _Harness(media: media)..connect();
        h.channel.syncPresence([
          presenceEntry(_me, joinedSeconds: 10),
          presenceEntry(_other, ready: 'ready', file: 'movie.mkv'),
        ]);
        async.elapse(const Duration(seconds: 5));
        h.channel.sent.clear();

        h.service.retrackReadiness(ReadyStatus.ready, loadedFileName: 'movie.mkv');
        async.flushMicrotasks();

        expect(h.channel.hasSent(SyncEventType.stateRequest), isTrue);
        h.dispose();
      });
    });
  });

  group('C4 reconnect and teardown', () {
    test('a dropped channel schedules a reconnect with backoff', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        expect(h.backend.channels, hasLength(1));

        h.channel.emitStatus(SyncSubscribeStatus.channelError);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(h.backend.channels, hasLength(2));
        h.dispose();
      });
    });

    test('the backoff grows across successive drops', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.emitStatus(SyncSubscribeStatus.channelError);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(h.backend.channels, hasLength(2));

        h.channel.emitStatus(SyncSubscribeStatus.channelError);
        async.elapse(const Duration(milliseconds: 1500));
        async.flushMicrotasks();
        expect(h.backend.channels, hasLength(2), reason: '2s backoff has not elapsed');

        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(h.backend.channels, hasLength(3));

        h.dispose();
      });
    });

    test('an intentional disconnect does not schedule a reconnect', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        final channel = h.channel;

        h.service.disconnect();
        async.flushMicrotasks();
        channel.emitStatus(SyncSubscribeStatus.closed);
        async.elapse(const Duration(seconds: 30));

        expect(h.backend.channels, hasLength(1));
        h.dispose();
      });
    });

    test('a superseded channel reporting closed does not start another reconnect', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        final stale = h.channel;

        stale.emitStatus(SyncSubscribeStatus.channelError);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(h.backend.channels, hasLength(2));

        stale.emitStatus(SyncSubscribeStatus.closed);
        async.elapse(const Duration(seconds: 30));

        expect(h.backend.channels, hasLength(2));
        h.dispose();
      });
    });

    test('a drop then a resubscribe drives the reconnecting banner both ways', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();
        expect(h.connectionEvents, [true]);

        h.channel.emitStatus(SyncSubscribeStatus.channelError);
        async.elapse(const Duration(seconds: 1));
        h.channel.emitStatus(SyncSubscribeStatus.subscribed);
        async.flushMicrotasks();

        expect(h.connectionEvents, [true, false, true]);
        h.dispose();
      });
    });

    test('resubscribing re-announces presence and refetches canonical media', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.emitStatus(SyncSubscribeStatus.channelError);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        h.channel.emitStatus(SyncSubscribeStatus.subscribed);
        async.flushMicrotasks();

        expect(h.channel.tracked, isNotEmpty);
        expect(h.channel.hasSent(SyncEventType.stateRequest), isTrue);
        h.dispose();
      });
    });

    test('readiness survives a reconnect and is re-announced', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        h.service.retrackReadiness(ReadyStatus.ready, loadedFileName: 'movie.mkv');
        async.flushMicrotasks();

        h.channel.emitStatus(SyncSubscribeStatus.channelError);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        h.channel.emitStatus(SyncSubscribeStatus.subscribed);
        async.flushMicrotasks();

        expect(h.channel.tracked.last['ready_status'], 'ready');
        expect(h.channel.tracked.last['loaded_file_name'], 'movie.mkv');
        h.dispose();
      });
    });
  });

  group('C5 attribution stays user-initiated', () {
    test('a human play is attributed', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.play, {'senderId': _other, 'timestamp': 100});
        async.flushMicrotasks();

        expect(h.actions, hasLength(1));
        expect(h.actions.single.kind, RemoteActionKind.play);
        expect(h.actions.single.senderId, _other);
        h.dispose();
      });
    });

    test('a gate-reason play or pause raises no toast', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.pause, {
          'senderId': _other,
          'timestamp': 100,
          'reason': SyncActionReason.gate,
        });
        async.elapse(const Duration(milliseconds: 200));
        h.channel.deliver(SyncEventType.play, {
          'senderId': _other,
          'timestamp': 200,
          'reason': SyncActionReason.gate,
        });
        async.elapse(const Duration(milliseconds: 200));

        expect(h.remotePauses, hasLength(1));
        expect(h.remotePlays, hasLength(1));
        expect(h.actions, isEmpty);
        h.dispose();
      });
    });

    test('a mechanical seek raises no toast but is still applied', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.seek, {
          'senderId': _other,
          'timestamp': 100,
          'positionMs': 5000,
          'reason': SyncActionReason.transport,
        });
        async.flushMicrotasks();

        expect(h.remoteSeeks, [const Duration(seconds: 5)]);
        expect(h.actions, isEmpty);
        h.dispose();
      });
    });

    test('state_response never toasts, so late-join is silent', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.stateResponse, {
          'senderId': _other,
          'timestamp': 100,
          'playing': true,
          'positionMs': 30000,
          'mode': 'local',
        });
        async.elapse(const Duration(seconds: 1));

        expect(h.remotePlays, hasLength(1));
        expect(h.actions, isEmpty);
        h.dispose();
      });
    });

    test('drift correction never toasts and routes to the silent hook', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        h.player.playingValue = true;
        h.service.isPlaying = () => true;
        h.service.currentPosition = () => const Duration(seconds: 10);
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.positionSync, {
          'senderId': _other,
          'timestamp': 100,
          'positionMs': 30000,
          'playing': true,
        });
        async.flushMicrotasks();

        expect(h.driftCorrections, [const Duration(seconds: 30)]);
        expect(h.remoteSeeks, isEmpty);
        expect(h.actions, isEmpty);
        h.dispose();
      });
    });

    test('drift within the threshold corrects nothing', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        h.service.isPlaying = () => true;
        h.service.currentPosition = () => const Duration(seconds: 30);
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.positionSync, {
          'senderId': _other,
          'timestamp': 100,
          'positionMs': 31000,
          'playing': true,
        });
        async.flushMicrotasks();

        expect(h.driftCorrections, isEmpty);
        h.dispose();
      });
    });
  });

  group('C5 reactions never touch playback', () {
    test('an incoming reaction does not advance the applied watermark', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.reaction, {
          'senderId': _other,
          'timestamp': 999999,
          'emoji': '👏',
          'displayName': 'Ada',
        });
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.play, {'senderId': _other, 'timestamp': 100});
        async.flushMicrotasks();

        expect(h.remotePlays, hasLength(1), reason: 'the reaction ate the next real play');
        h.dispose();
      });
    });

    test('an incoming reaction never feeds attribution', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.reaction, {
          'senderId': _other,
          'timestamp': 100,
          'emoji': '👏',
          'displayName': 'Ada',
        });
        async.flushMicrotasks();

        expect(h.reactions, hasLength(1));
        expect(h.actions, isEmpty);
        expect(h.remotePlays, isEmpty);
        expect(h.remotePauses, isEmpty);
        expect(h.remoteSeeks, isEmpty);
        h.dispose();
      });
    });

    test('an emoji we did not bundle is rejected on receive', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.reaction, {
          'senderId': _other,
          'timestamp': 100,
          'emoji': '🦆',
          'displayName': 'Ada',
        });
        async.flushMicrotasks();

        expect(h.reactions, isEmpty);
        h.dispose();
      });
    });

    test('sending echoes locally and broadcasts, since the channel is self:false', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.service.sendReaction('👏');
        async.flushMicrotasks();

        expect(h.reactions, hasLength(1));
        expect(h.reactions.single.emoji, '👏');
        expect(h.channel.hasSent(SyncEventType.reaction), isTrue);
        h.dispose();
      });
    });

    test('an unbundled emoji is rejected on send too', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.service.sendReaction('🦆');
        async.flushMicrotasks();

        expect(h.reactions, isEmpty);
        expect(h.channel.hasSent(SyncEventType.reaction), isFalse);
        h.dispose();
      });
    });

    test('a burst echoes every tap locally while capping the wire', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.service.sendReaction('👏');
        h.service.sendReaction('😂');
        h.service.sendReaction('🎉');
        async.flushMicrotasks();

        expect(h.reactions, hasLength(3), reason: 'local echo is never throttled');
        expect(h.channel.sentOf(SyncEventType.reaction), hasLength(1));

        async.elapse(const Duration(milliseconds: 250));
        expect(h.channel.sentOf(SyncEventType.reaction), hasLength(2));
        expect(
          h.channel.lastOf(SyncEventType.reaction)!.payload['emoji'],
          '🎉',
          reason: 'the last emoji of a burst must still transmit',
        );
        h.dispose();
      });
    });

    test('a reaction is never gated by the transport lock', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.transportLock, {
          'senderId': 'host',
          'timestamp': 100,
          'locked': true,
        });
        async.flushMicrotasks();
        expect(h.service.transportLock, isTrue);

        h.service.sendReaction('👏');
        async.flushMicrotasks();

        expect(h.reactions, hasLength(1));
        expect(h.channel.hasSent(SyncEventType.reaction), isTrue);
        h.dispose();
      });
    });
  });

  group('canonical media adoption', () {
    RoomMedia mediaAt(String name, DateTime stamp) =>
        RoomMedia(kind: RoomMediaKind.local, name: name, updatedAt: stamp);

    test('a newer media_set broadcast is adopted', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.mediaSet, {
          'senderId': 'host',
          'timestamp': 100,
          'kind': 'local',
          'name': 'movie.mkv',
          'updatedAtMs': DateTime.utc(2026, 7, 31, 10, 30).millisecondsSinceEpoch,
        });
        async.flushMicrotasks();

        expect(h.service.canonicalMedia.name, 'movie.mkv');
        h.dispose();
      });
    });

    test('a stale refetch cannot clobber a newer broadcast already applied', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        h.backend.roomRow = testRoom(media: mediaAt('old.mkv', DateTime.utc(2026, 7, 31, 10)));
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.mediaSet, {
          'senderId': 'host',
          'timestamp': 100,
          'kind': 'local',
          'name': 'new.mkv',
          'updatedAtMs': DateTime.utc(2026, 7, 31, 11).millisecondsSinceEpoch,
        });
        async.flushMicrotasks();

        h.service.refreshCanonicalMedia();
        async.flushMicrotasks();

        expect(h.service.canonicalMedia.name, 'new.mkv');
        h.dispose();
      });
    });

    test('a re-delivered media_set does not re-emit to listeners', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        final adopted = <RoomMedia>[];
        h.service.canonicalMediaStream.listen(adopted.add);
        async.flushMicrotasks();

        final payload = {
          'senderId': 'host',
          'timestamp': 100,
          'kind': 'local',
          'name': 'movie.mkv',
          'updatedAtMs': DateTime.utc(2026, 7, 31, 10, 30).millisecondsSinceEpoch,
        };
        h.channel.deliver(SyncEventType.mediaSet, payload);
        h.channel.deliver(SyncEventType.mediaSet, payload);
        async.flushMicrotasks();

        expect(adopted, hasLength(1));
        h.dispose();
      });
    });
  });

  group('kick and room end', () {
    test('only the named target is evicted', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        var kicked = 0;
        h.service.kickedStream.listen((_) => kicked++);
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.memberKicked, {
          'senderId': 'host',
          'timestamp': 100,
          'targetUserId': _other,
        });
        async.flushMicrotasks();
        expect(kicked, 0);

        h.channel.deliver(SyncEventType.memberKicked, {
          'senderId': 'host',
          'timestamp': 200,
          'targetUserId': _me,
        });
        async.flushMicrotasks();
        expect(kicked, 1);

        h.dispose();
      });
    });

    test('room_ended reaches every member', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        var ended = 0;
        h.service.roomEndedStream.listen((_) => ended++);
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.roomEnded, {'senderId': 'host', 'timestamp': 100});
        async.flushMicrotasks();

        expect(ended, 1);
        h.dispose();
      });
    });

    test('a deleted room carries its reason, so the copy can say it is gone', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        final reasons = <String?>[];
        h.service.roomEndedStream.listen(reasons.add);
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.roomEnded, {
          'senderId': 'server',
          'timestamp': 100,
          'reason': 'deleted',
        });
        async.flushMicrotasks();

        expect(reasons, ['deleted']);
        h.dispose();
      });
    });

    test('an eviction with no reason still evicts, for older senders', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        final reasons = <String?>[];
        h.service.roomEndedStream.listen(reasons.add);
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.roomEnded, {'senderId': 'host', 'timestamp': 100});
        async.flushMicrotasks();

        expect(reasons, [null]);
        h.dispose();
      });
    });
  });

  group('gate waiver', () {
    test('the host can start without a straggler, and everyone agrees', () {
      fakeAsync((async) {
        final media = RoomMedia(
          kind: RoomMediaKind.local,
          name: 'movie.mkv',
          updatedAt: DateTime.utc(2026, 8, 4),
        );
        final h = _Harness(role: 'host', media: media, joinedSeconds: 0)..connect();
        async.flushMicrotasks();

        h.service.retrackReadiness(ReadyStatus.ready, loadedFileName: 'movie.mkv');
        h.channel.syncPresence([
          presenceEntry(_me, role: 'host', joinedSeconds: 0, ready: 'ready', file: 'movie.mkv'),
          presenceEntry(_other, joinedSeconds: 10),
        ]);
        async.flushMicrotasks();
        expect(h.service.gateState, GateState.closed);
        expect(h.service.gateBlockers.map((m) => m.userId), [_other]);

        unawaited(h.service.waiveGateBlockers());
        async.flushMicrotasks();

        expect(h.service.gateState, GateState.open);
        expect(h.service.waivedMembers, {_other});
        expect(h.channel.sentOf(SyncEventType.gateWaiver), hasLength(1));
        expect(h.channel.sentOf(SyncEventType.gateWaiver).single.payload['userIds'], [_other]);

        h.dispose();
      });
    });

    test('a member adopts the waiver it receives, so the room agrees', () {
      fakeAsync((async) {
        final media = RoomMedia(
          kind: RoomMediaKind.local,
          name: 'movie.mkv',
          updatedAt: DateTime.utc(2026, 8, 4),
        );
        final h = _Harness(media: media, joinedSeconds: 10)..connect();
        async.flushMicrotasks();

        h.service.retrackReadiness(ReadyStatus.ready, loadedFileName: 'movie.mkv');
        h.channel.syncPresence([
          presenceEntry('host', role: 'host', joinedSeconds: 0, ready: 'ready', file: 'movie.mkv'),
          presenceEntry(_me, joinedSeconds: 10, ready: 'ready', file: 'movie.mkv'),
          presenceEntry('slow', joinedSeconds: 20),
        ]);
        async.flushMicrotasks();
        expect(h.service.gateState, GateState.closed);

        h.channel.deliver(SyncEventType.gateWaiver, {
          'senderId': 'host',
          'timestamp': 500,
          'userIds': ['slow'],
        });
        async.flushMicrotasks();

        expect(h.service.gateState, GateState.open);
        h.dispose();
      });
    });

    test('a waiver never survives a change of media', () {
      fakeAsync((async) {
        final media = RoomMedia(
          kind: RoomMediaKind.local,
          name: 'movie.mkv',
          updatedAt: DateTime.utc(2026, 8, 4),
        );
        final h = _Harness(role: 'host', media: media, joinedSeconds: 0)..connect();
        async.flushMicrotasks();

        h.service.retrackReadiness(ReadyStatus.ready, loadedFileName: 'movie.mkv');
        h.channel.syncPresence([
          presenceEntry(_me, role: 'host', joinedSeconds: 0, ready: 'ready', file: 'movie.mkv'),
          presenceEntry(_other, joinedSeconds: 10),
        ]);
        async.flushMicrotasks();
        unawaited(h.service.waiveGateBlockers());
        async.flushMicrotasks();
        expect(h.service.waivedMembers, {_other});

        h.channel.deliver(SyncEventType.mediaSet, {
          'senderId': 'host',
          'timestamp': 900,
          'kind': 'local',
          'name': 'sequel.mkv',
          'updatedAtMs': DateTime.utc(2026, 8, 5).millisecondsSinceEpoch,
        });
        async.flushMicrotasks();

        expect(h.service.waivedMembers, isEmpty);
        h.dispose();
      });
    });

    test('a member cannot waive anyone, whatever they call', () {
      fakeAsync((async) {
        final media = RoomMedia(
          kind: RoomMediaKind.local,
          name: 'movie.mkv',
          updatedAt: DateTime.utc(2026, 8, 4),
        );
        final h = _Harness(media: media, joinedSeconds: 10)..connect();
        async.flushMicrotasks();

        h.channel.syncPresence([
          presenceEntry('host', role: 'host', joinedSeconds: 0, ready: 'ready', file: 'movie.mkv'),
          presenceEntry(_me, joinedSeconds: 10),
        ]);
        async.flushMicrotasks();

        unawaited(h.service.waiveGateBlockers());
        async.flushMicrotasks();

        expect(h.service.waivedMembers, isEmpty);
        expect(h.channel.sentOf(SyncEventType.gateWaiver), isEmpty);
        h.dispose();
      });
    });
  });

  group('chat', () {
    test('a sent message broadcasts and persists', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        async.flushMicrotasks();

        h.service.sendChat('hello there');
        async.flushMicrotasks();

        expect(h.channel.hasSent(SyncEventType.chat), isTrue);
        expect(h.backend.insertedChat, ['hello there']);
        h.dispose();
      });
    });

    test('an incoming chat reaches the transcript', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        final received = <ChatMessage>[];
        h.service.chatMessages.listen(received.add);
        async.flushMicrotasks();

        h.channel.deliver(SyncEventType.chat, {
          'senderId': _other,
          'timestamp': DateTime.utc(2026, 7, 31, 11).millisecondsSinceEpoch,
          'displayName': 'Ada',
          'message': 'hi',
        });
        async.flushMicrotasks();

        expect(received.single.content, 'hi');
        expect(received.single.displayName, 'Ada');
        h.dispose();
      });
    });
  });

  group('presence coalescing', () {
    test('a readiness burst does not flood the wire', () {
      fakeAsync((async) {
        final h = _Harness(role: 'host')..connect();
        h.channel.tracked.clear();

        h.service.retrackReadiness(.selecting);
        h.service.retrackReadiness(.none);
        h.service.retrackReadiness(.selecting);
        h.service.retrackReadiness(.none);
        h.service.retrackReadiness(.ready, loadedFileName: 'movie.mkv');
        async.elapse(const Duration(seconds: 40));

        expect(h.channel.tracked.length, lessThanOrEqualTo(SyncService.kPresenceMaxCalls));
      });
    });

    test('the final readiness always reaches the wire, so the gate cannot strand', () {
      fakeAsync((async) {
        final h = _Harness(role: 'host')..connect();
        h.channel.tracked.clear();

        h.service.retrackReadiness(.selecting);
        h.service.retrackReadiness(.none);
        h.service.retrackReadiness(.ready, loadedFileName: 'movie.mkv');
        async.elapse(const Duration(seconds: 40));

        final last = h.channel.tracked.last;
        expect(last['ready_status'], 'ready');
        expect(last['loaded_file_name'], 'movie.mkv');
      });
    });

    test('a lone readiness change still lands without waiting on another', () {
      fakeAsync((async) {
        final h = _Harness(role: 'host')..connect();
        h.channel.tracked.clear();

        h.service.retrackReadiness(.ready, loadedFileName: 'movie.mkv');
        async.elapse(const Duration(seconds: 40));

        expect(h.channel.tracked.last['ready_status'], 'ready');
      });
    });

    test('a role change during a burst is not lost', () {
      fakeAsync((async) {
        final h = _Harness(role: 'member')..connect();
        h.channel.tracked.clear();

        h.service.retrackReadiness(.selecting);
        h.service.updateRole('host');
        async.elapse(const Duration(seconds: 40));

        expect(h.channel.tracked.last['role'], 'host');
      });
    });
  });

  group('media sharing sync & late joiner auto-waiver', () {
    test('broadcastUploadProgress throttles small progress increments within 3s', () {
      fakeAsync((async) {
        final h = _Harness(role: 'host')..connect();
        h.channel.sent.clear();

        h.service.broadcastUploadProgress(
          fraction: 0.10,
          speedBps: 1000000,
          etaSeconds: 50,
          state: 'uploading',
        );
        async.flushMicrotasks();
        expect(h.channel.hasSent(SyncEventType.uploadProgress), isTrue);
        h.channel.sent.clear();

        // 1 second later with only +1% delta: should be throttled
        async.elapse(const Duration(seconds: 1));
        h.service.broadcastUploadProgress(
          fraction: 0.11,
          speedBps: 1000000,
          etaSeconds: 49,
          state: 'uploading',
        );
        async.flushMicrotasks();
        expect(h.channel.hasSent(SyncEventType.uploadProgress), isFalse);

        // 1 second later but with >=5% delta: should broadcast
        async.elapse(const Duration(seconds: 1));
        h.service.broadcastUploadProgress(
          fraction: 0.17,
          speedBps: 1000000,
          etaSeconds: 45,
          state: 'uploading',
        );
        async.flushMicrotasks();
        expect(h.channel.hasSent(SyncEventType.uploadProgress), isTrue);
        h.channel.sent.clear();

        // >=3 seconds later: should broadcast even with small delta
        async.elapse(const Duration(seconds: 4));
        h.service.broadcastUploadProgress(
          fraction: 0.18,
          speedBps: 1000000,
          etaSeconds: 44,
          state: 'uploading',
        );
        async.flushMicrotasks();
        expect(h.channel.hasSent(SyncEventType.uploadProgress), isTrue);

        h.dispose();
      });
    });

    test('broadcastSharingToggled broadcasts toggled state to channel', () {
      fakeAsync((async) {
        final h = _Harness(role: 'host')..connect();
        h.channel.sent.clear();

        h.service.broadcastSharingToggled(
          enabled: true,
          fileName: 'movie.mp4',
          fileSize: 50000000,
          uploadState: 'uploading',
        );

        expect(h.channel.hasSent(SyncEventType.sharingToggled), isTrue);
        final sentPayload = h.channel.sent.first.payload;
        expect(sentPayload['enabled'], isTrue);
        expect(sentPayload['fileName'], 'movie.mp4');
        expect(sentPayload['fileSize'], 50000000);
        expect(sentPayload['uploadState'], 'uploading');

        h.dispose();
      });
    });

    test('incoming uploadProgress and sharingToggled events reach streams and update state', () {
      fakeAsync((async) {
        final h = _Harness(role: 'member')..connect();
        final progressEvents = <UploadProgressEvent>[];
        final toggleEvents = <SharingToggledEvent>[];

        h.service.uploadProgressStream.listen(progressEvents.add);
        h.service.sharingToggledStream.listen(toggleEvents.add);

        h.channel.deliver(SyncEventType.uploadProgress, {
          'senderId': 'host',
          'timestamp': 100,
          'fraction': 0.45,
          'speedBps': 5000000.0,
          'etaSeconds': 20,
          'state': 'uploading',
        });

        h.channel.deliver(SyncEventType.sharingToggled, {
          'senderId': 'host',
          'timestamp': 101,
          'enabled': true,
          'fileName': 'movie.mp4',
          'fileSize': 100000000,
          'uploadState': 'uploading',
        });

        async.flushMicrotasks();

        expect(progressEvents, hasLength(1));
        expect(progressEvents.first.fraction, 0.45);
        expect(h.service.mediaUploadState, 'uploading');

        expect(toggleEvents, hasLength(1));
        expect(toggleEvents.first.enabled, isTrue);

        h.dispose();
      });
    });

    test('late joiner is automatically waived by authority when room is playing ready shared media', () {
      fakeAsync((async) {
        final h = _Harness(role: 'host', media: const RoomMedia(kind: .local, name: 'movie.mkv'))..connect();
        h.service.setMediaUploadState('ready');
        h.service.broadcastPlay();
        async.flushMicrotasks();

        expect(h.service.roomPlaying, isTrue);

        // Host is ready
        h.channel.syncPresence([
          {'user_id': _me, 'role': 'host', 'ready_status': 'ready', 'loaded_file_name': 'movie.mkv'},
        ]);
        async.flushMicrotasks();

        expect(h.service.gateState, GateState.open);

        // Late joiner arrives not ready
        h.channel.syncPresence([
          {'user_id': _me, 'role': 'host', 'ready_status': 'ready', 'loaded_file_name': 'movie.mkv'},
          {'user_id': 'late_joiner', 'role': 'member', 'ready_status': 'none'},
        ]);
        async.flushMicrotasks();

        // Late joiner is waived, gate stays open (no pause!)
        expect(h.service.waivedMembers, contains('late_joiner'));
        expect(h.service.gateState, GateState.open);

        // Late joiner becomes ready: waiver is cleared, gate still open
        h.channel.syncPresence([
          {'user_id': _me, 'role': 'host', 'ready_status': 'ready', 'loaded_file_name': 'movie.mkv'},
          {'user_id': 'late_joiner', 'role': 'member', 'ready_status': 'ready', 'loaded_file_name': 'movie.mkv'},
        ]);
        async.flushMicrotasks();

        expect(h.service.waivedMembers, isNot(contains('late_joiner')));
        expect(h.service.gateState, GateState.open);

        h.dispose();
      });
    });

    test('broadcastRoomExtended broadcasts and notifies listeners', () {
      fakeAsync((async) {
        final h = _Harness()..connect();
        RoomExtendedEvent? received;
        h.service.roomExtendedStream.listen((event) => received = event);
        async.flushMicrotasks();

        final expiry = DateTime.now().add(const Duration(hours: 2)).toIso8601String();
        h.service.broadcastRoomExtended(expiresAt: expiry, durationMinutes: 120);
        async.flushMicrotasks();

        expect(h.channel.sent.last.event, SyncEventType.roomExtended);
        expect(h.channel.sent.last.payload['expiresAt'], expiry);
        expect(h.channel.sent.last.payload['durationMinutes'], 120);

        h.channel.deliver(SyncEventType.roomExtended, {
          'senderId': 'host',
          'timestamp': 100,
          'expiresAt': expiry,
          'durationMinutes': 120,
        });
        async.flushMicrotasks();

        expect(received, isNotNull);
        expect(received!.expiresAt, expiry);
        expect(received!.durationMinutes, 120);

        h.dispose();
      });
    });
  });
}
