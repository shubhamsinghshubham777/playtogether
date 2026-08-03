import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/analytics.dart';

class _RecordingTransport {
  _RecordingTransport({this.succeed = true});

  bool succeed;
  final calls = <List<Map<String, dynamic>>>[];
  final endpoints = <Uri>[];

  Future<bool> call(Uri endpoint, String body) async {
    endpoints.add(endpoint);
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    calls.add((decoded['batch'] as List).map((e) => (e as Map).cast<String, dynamic>()).toList());
    return succeed;
  }

  List<String> get eventNames =>
      calls.expand((batch) => batch).map((e) => e['event'] as String).toList();
}

Analytics _configured(_RecordingTransport transport, {String? apiKey = 'phc_test', String? host}) {
  return Analytics()..init(
    apiKey: apiKey,
    host: host,
    distinctId: 'user-1',
    context: {'platform': 'macOS'},
    transport: transport.call,
  );
}

void main() {
  group('no key', () {
    test('stays disabled and queues nothing', () {
      final transport = _RecordingTransport();
      final analytics = _configured(transport, apiKey: null);

      analytics.track('app_opened');
      analytics.identify('user-2');

      expect(analytics.isEnabled, isFalse);
      expect(analytics.distinctId, isNull);
      expect(analytics.queuedCount, 0);
      expect(transport.calls, isEmpty);
    });

    test('an empty key is treated the same as a missing one', () {
      final analytics = _configured(_RecordingTransport(), apiKey: '');
      expect(analytics.isEnabled, isFalse);
    });
  });

  test('events below the threshold wait for the timer', () {
    fakeAsync((async) {
      final transport = _RecordingTransport();
      final analytics = _configured(transport);

      analytics.track('app_opened');
      analytics.track('room_created');
      async.elapse(const Duration(seconds: 29));
      expect(transport.calls, isEmpty);
      expect(analytics.queuedCount, 2);

      async.elapse(const Duration(seconds: 2));
      expect(transport.calls, hasLength(1));
      expect(transport.eventNames, ['app_opened', 'room_created']);
      expect(analytics.queuedCount, 0);
    });
  });

  test('the twentieth event flushes without waiting', () {
    fakeAsync((async) {
      final transport = _RecordingTransport();
      final analytics = _configured(transport);

      for (var i = 0; i < 19; i++) {
        analytics.track('reaction_sent');
      }
      async.flushMicrotasks();
      expect(transport.calls, isEmpty);

      analytics.track('reaction_sent');
      async.flushMicrotasks();
      expect(transport.calls, hasLength(1));
      expect(transport.calls.single, hasLength(20));
    });
  });

  test('the batch carries the api key, context and identity', () {
    fakeAsync((async) {
      final transport = _RecordingTransport();
      final analytics = _configured(transport);

      analytics.track('room_joined', {'via': 'deeplink'});
      async.elapse(const Duration(seconds: 31));

      final event = transport.calls.single.single;
      expect(event['event'], 'room_joined');
      expect(event['distinct_id'], 'user-1');
      expect(event['timestamp'], isA<String>());
      final properties = (event['properties'] as Map).cast<String, dynamic>();
      expect(properties['via'], 'deeplink');
      expect(properties['platform'], 'macOS');
      expect(transport.endpoints.single.toString(), 'https://us.i.posthog.com/batch/');
    });
  });

  test('a host override replaces the default, trailing slash and all', () {
    fakeAsync((async) {
      final transport = _RecordingTransport();
      final analytics = _configured(transport, host: 'https://eu.i.posthog.com/');

      analytics.track('app_opened');
      async.elapse(const Duration(seconds: 31));

      expect(transport.endpoints.single.toString(), 'https://eu.i.posthog.com/batch/');
    });
  });

  test('a failed batch is kept and retried on the next flush', () {
    fakeAsync((async) {
      final transport = _RecordingTransport(succeed: false);
      final analytics = _configured(transport);

      analytics.track('app_opened');
      async.elapse(const Duration(seconds: 31));
      expect(transport.calls, hasLength(1));
      expect(analytics.queuedCount, 1);

      transport.succeed = true;
      async.elapse(const Duration(seconds: 31));
      expect(transport.calls, hasLength(2));
      expect(transport.calls.last.single['event'], 'app_opened');
      expect(analytics.queuedCount, 0);
    });
  });

  test('a throwing transport loses nothing either', () {
    fakeAsync((async) {
      var attempts = 0;
      final analytics = Analytics()
        ..init(
          apiKey: 'phc_test',
          distinctId: 'user-1',
          transport: (_, _) async {
            attempts++;
            throw const SocketExceptionStub();
          },
        );

      analytics.track('app_opened');
      async.elapse(const Duration(seconds: 31));

      expect(attempts, 1);
      expect(analytics.queuedCount, 1);
    });
  });

  test('the queue drops oldest past its cap rather than growing forever', () {
    fakeAsync((async) {
      final transport = _RecordingTransport(succeed: false);
      final analytics = _configured(transport);

      for (var i = 0; i < 700; i++) {
        analytics.track('reaction_sent', {'n': i});
      }
      async.elapse(const Duration(seconds: 31));

      expect(analytics.queuedCount, lessThanOrEqualTo(500));
      expect(analytics.queuedCount, greaterThan(0));
    });
  });

  test('identify aliases an anonymous run and switches distinct id', () {
    fakeAsync((async) {
      final transport = _RecordingTransport();
      final analytics = Analytics()..init(apiKey: 'phc_test', transport: transport.call);

      final anonymousId = analytics.distinctId;
      expect(anonymousId, isNotNull);

      analytics.track('app_opened');
      analytics.identify('user-9', personProperties: {'is_guest': true});
      analytics.track('signed_in');
      async.elapse(const Duration(seconds: 31));

      final batch = transport.calls.single;
      expect(batch.map((e) => e['event']), ['app_opened', r'$identify', 'signed_in']);
      expect(batch[0]['distinct_id'], anonymousId);
      expect(batch[1]['distinct_id'], 'user-9');
      expect(batch[2]['distinct_id'], 'user-9');

      final identifyProps = (batch[1]['properties'] as Map).cast<String, dynamic>();
      expect(identifyProps[r'$anon_distinct_id'], anonymousId);
      expect((identifyProps[r'$set'] as Map)['is_guest'], isTrue);
    });
  });

  test('identifying a user who was already known does not re-alias', () {
    fakeAsync((async) {
      final transport = _RecordingTransport();
      final analytics = _configured(transport);

      analytics.identify('user-1');
      analytics.track('app_opened');
      async.elapse(const Duration(seconds: 31));

      expect(transport.eventNames, ['app_opened']);
    });
  });

  test('a signed-in start never emits an alias', () {
    fakeAsync((async) {
      final transport = _RecordingTransport();
      final analytics = _configured(transport);

      analytics.identify('user-2');
      async.elapse(const Duration(seconds: 31));

      final properties = (transport.calls.single.single['properties'] as Map)
          .cast<String, dynamic>();
      expect(properties.containsKey(r'$anon_distinct_id'), isFalse);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
