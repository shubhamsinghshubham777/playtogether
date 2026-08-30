import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/rooms/reactions.dart';

typedef ReactionFetcher = Future<List<int>> Function(Uri url);

class ReactionCdn {
  ReactionCdn({ReactionFetcher? fetcher, DateTime Function()? now})
    : _fetch = fetcher ?? _get,
      _now = now ?? DateTime.now;

  static final instance = ReactionCdn();

  /// The overlay resolves compositions per *frame*, so a failed fetch that
  /// stayed instantly retryable would open a fresh socket 60 times a second
  /// for as long as an unresolved reaction is on screen.
  static const retryAfter = Duration(minutes: 1);

  final ReactionFetcher _fetch;
  final DateTime Function() _now;
  final _cache = <String, List<int>>{};
  final _inFlight = <String, Future<List<int>?>>{};
  final _rejected = <String>{};
  final _failedAt = <String, DateTime>{};

  List<int>? cached(PTReaction reaction) => _cache[reaction.codepoint];

  bool isRejected(PTReaction reaction) => _rejected.contains(reaction.codepoint);

  Future<List<int>?> load(PTReaction reaction) {
    final digest = reaction.digest;
    if (digest == null) return Future.value(null);
    final cached = _cache[reaction.codepoint];
    if (cached != null) return Future.value(cached);
    if (_rejected.contains(reaction.codepoint)) return Future.value(null);
    final failedAt = _failedAt[reaction.codepoint];
    if (failedAt != null && _now().difference(failedAt) < retryAfter) {
      return Future.value(null);
    }
    return _inFlight[reaction.codepoint] ??= _loadOnce(reaction, digest);
  }

  Future<List<int>?> _loadOnce(PTReaction reaction, String digest) async {
    try {
      final bytes = await _fetch(Uri.parse(reaction.cdnUrl));
      if (sha256.convert(bytes).toString() != digest) {
        _rejected.add(reaction.codepoint);
        reportNonFatal(
          StateError('reaction ${reaction.codepoint} did not match its pinned digest'),
          StackTrace.current,
          during: 'fetching an extended reaction animation',
        );
        return null;
      }
      if (!_isPlayableLottie(bytes)) {
        _rejected.add(reaction.codepoint);
        return null;
      }
      _cache[reaction.codepoint] = bytes;
      _failedAt.remove(reaction.codepoint);
      return bytes;
    } catch (e) {
      _failedAt[reaction.codepoint] = _now();
      // Offline or a flaky CDN is the documented normal path here: the overlay
      // falls back to the glyph and retries later, so this is a breadcrumb
      // rather than a fault.
      trace(
        'extended reaction fetch failed',
        category: 'media',
        data: {'codepoint': reaction.codepoint, 'error': e.runtimeType.toString()},
      );
      return null;
    } finally {
      _inFlight.remove(reaction.codepoint);
    }
  }

  static bool _isPlayableLottie(List<int> bytes) {
    try {
      final doc = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return doc['layers'] != null && doc['op'] != null && doc['fr'] != null;
    } catch (_) {
      return false;
    }
  }

  static Future<List<int>> _get(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException('status ${response.statusCode}', uri: url);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > _maxBytes) {
          throw HttpException('reaction animation over $_maxBytes bytes', uri: url);
        }
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static const _maxBytes = 2 * 1024 * 1024;
}
