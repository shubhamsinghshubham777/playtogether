import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:playtogether/diagnostics.dart';
import 'package:uuid/uuid.dart';

typedef AnalyticsTransport = Future<bool> Function(Uri endpoint, String body);

const kAnalyticsDefaultHost = 'https://us.i.posthog.com';
const _kFlushInterval = Duration(seconds: 30);
const _kFlushThreshold = 20;
const _kMaxQueued = 500;
const _kMaxPerBatch = 100;
const _kFailuresBeforeTrace = 3;

class Analytics {
  Analytics();

  static final instance = Analytics();

  String? _apiKey;
  Uri? _endpoint;
  AnalyticsTransport _transport = _postBatch;

  String? _distinctId;
  bool _distinctIdIsAnonymous = false;
  Map<String, Object?> _context = const {};

  final _queue = <Map<String, Object?>>[];
  Timer? _timer;
  bool _sending = false;
  int _consecutiveFailures = 0;
  bool _failureTraced = false;

  bool get isEnabled => _apiKey != null;

  String? get distinctId => _distinctId;

  int get queuedCount => _queue.length;

  void init({
    required String? apiKey,
    String? host,
    String? distinctId,
    Map<String, Object?> context = const {},
    AnalyticsTransport? transport,
  }) {
    if (apiKey == null || apiKey.isEmpty) return;
    _apiKey = apiKey;
    final base = (host == null || host.isEmpty) ? kAnalyticsDefaultHost : host;
    _endpoint = Uri.parse(
      '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}/batch/',
    );
    if (transport != null) _transport = transport;
    _distinctIdIsAnonymous = distinctId == null || distinctId.isEmpty;
    _distinctId = _distinctIdIsAnonymous ? const Uuid().v4() : distinctId;
    _context = context;
  }

  void track(String event, [Map<String, Object?> properties = const {}]) {
    if (!isEnabled) return;
    _enqueue(event, {..._context, ...properties});
  }

  void identify(String userId, {Map<String, Object?> personProperties = const {}}) {
    if (!isEnabled || userId.isEmpty) return;
    if (_distinctId == userId) return;
    final previous = _distinctId;
    final wasAnonymous = _distinctIdIsAnonymous;
    _distinctId = userId;
    _distinctIdIsAnonymous = false;
    _enqueue('\$identify', {
      ..._context,
      if (wasAnonymous && previous != null) '\$anon_distinct_id': previous,
      '\$set': {..._context, ...personProperties},
    });
  }

  Future<void> flush() async {
    if (!isEnabled || _sending || _queue.isEmpty) return;
    final endpoint = _endpoint;
    if (endpoint == null) return;
    _sending = true;
    final batch = _queue.take(_kMaxPerBatch).toList(growable: false);
    _queue.removeRange(0, batch.length);
    try {
      final body = jsonEncode({'api_key': _apiKey, 'batch': batch});
      final delivered = await _transport(endpoint, body);
      if (delivered) {
        _consecutiveFailures = 0;
        _failureTraced = false;
      } else {
        _requeue(batch);
      }
    } catch (_) {
      _requeue(batch);
    } finally {
      _sending = false;
      if (_queue.isEmpty) _stopTimer();
    }
  }

  void _enqueue(String event, Map<String, Object?> properties) {
    _queue.add({
      'event': event,
      'distinct_id': _distinctId,
      'properties': properties,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    _dropOverflow();
    if (_queue.length >= _kFlushThreshold) {
      unawaited(flush());
    } else {
      _startTimer();
    }
  }

  void _requeue(List<Map<String, Object?>> batch) {
    _queue.insertAll(0, batch);
    _dropOverflow();
    _consecutiveFailures++;
    if (_consecutiveFailures >= _kFailuresBeforeTrace && !_failureTraced) {
      _failureTraced = true;
      trace(
        'analytics delivery keeps failing',
        category: 'analytics',
        data: {'attempts': _consecutiveFailures, 'queued': _queue.length},
      );
    }
    _startTimer();
  }

  void _dropOverflow() {
    if (_queue.length <= _kMaxQueued) return;
    _queue.removeRange(0, _queue.length - _kMaxQueued);
  }

  void _startTimer() {
    _timer ??= Timer.periodic(_kFlushInterval, (_) => unawaited(flush()));
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}

Future<bool> _postBatch(Uri endpoint, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.write(body);
    final response = await request.close().timeout(const Duration(seconds: 20));
    await response.drain<void>();
    return response.statusCode >= 200 && response.statusCode < 300;
  } finally {
    client.close(force: true);
  }
}
