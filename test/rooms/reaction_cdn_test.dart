import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/rooms/reaction_cdn.dart';
import 'package:playtogether/rooms/reactions.dart';

const _lottie = '{"v":"5.0","fr":60,"op":120,"w":512,"h":512,"layers":[{"ty":4}]}';

List<int> get _bytes => utf8.encode(_lottie);

String get _digest => sha256.convert(_bytes).toString();

PTReaction _reaction({String? digest}) =>
    PTReaction(emoji: '🔥', codepoint: '1f525', label: 'Fire', digest: digest ?? _digest);

void main() {
  group('extended reaction fetch', () {
    test('serves bytes whose digest matches the pin', () async {
      final cdn = ReactionCdn(fetcher: (_) async => _bytes);
      expect(await cdn.load(_reaction()), _bytes);
    });

    test('refuses bytes whose digest does not match, however playable', () async {
      final cdn = ReactionCdn(
        fetcher: (_) async => utf8.encode('{"fr":60,"op":120,"layers":[{"ty":4}],"evil":1}'),
      );
      expect(await cdn.load(_reaction()), isNull);
      expect(cdn.isRejected(_reaction()), isTrue);
    });

    test('a rejected emoji is never retried, so a swap cannot be ground through', () async {
      var calls = 0;
      final cdn = ReactionCdn(
        fetcher: (_) async {
          calls++;
          return utf8.encode('tampered');
        },
      );
      await cdn.load(_reaction());
      await cdn.load(_reaction());
      expect(calls, 1);
    });

    test('refuses a digest-matching payload that is not a playable Lottie', () async {
      final junk = utf8.encode('not a lottie at all');
      final cdn = ReactionCdn(fetcher: (_) async => junk);
      final pinned = PTReaction(
        emoji: '🔥',
        codepoint: '1f525',
        label: 'Fire',
        digest: sha256.convert(junk).toString(),
      );
      expect(await cdn.load(pinned), isNull);
      expect(cdn.isRejected(pinned), isTrue);
    });

    test('a bundled reaction never touches the network', () async {
      var calls = 0;
      final cdn = ReactionCdn(
        fetcher: (_) async {
          calls++;
          return _bytes;
        },
      );
      expect(await cdn.load(kReactions.first), isNull);
      expect(calls, 0);
    });

    test('a second read is served from memory rather than refetched', () async {
      var calls = 0;
      final cdn = ReactionCdn(
        fetcher: (_) async {
          calls++;
          return _bytes;
        },
      );
      await cdn.load(_reaction());
      await cdn.load(_reaction());
      expect(calls, 1);
      expect(cdn.cached(_reaction()), _bytes);
    });

    test('concurrent reads share one request', () async {
      var calls = 0;
      final cdn = ReactionCdn(
        fetcher: (_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return _bytes;
        },
      );
      await Future.wait([cdn.load(_reaction()), cdn.load(_reaction()), cdn.load(_reaction())]);
      expect(calls, 1);
    });

    test('a network failure degrades to the glyph without rejecting the emoji', () async {
      var calls = 0;
      var clock = DateTime.utc(2026, 8, 4, 12);
      final cdn = ReactionCdn(
        now: () => clock,
        fetcher: (_) async {
          calls++;
          if (calls == 1) throw const SocketFailure();
          return _bytes;
        },
      );
      expect(await cdn.load(_reaction()), isNull);
      expect(cdn.isRejected(_reaction()), isFalse);

      clock = clock.add(ReactionCdn.retryAfter * 2);
      expect(await cdn.load(_reaction()), _bytes);
    });

    test('a failure does not reopen a socket every frame while it is on screen', () async {
      var calls = 0;
      var clock = DateTime.utc(2026, 8, 4, 12);
      final cdn = ReactionCdn(
        now: () => clock,
        fetcher: (_) async {
          calls++;
          throw const SocketFailure();
        },
      );

      for (var frame = 0; frame < 120; frame++) {
        clock = clock.add(const Duration(milliseconds: 16));
        await cdn.load(_reaction());
      }

      expect(calls, 1);
    });

    test('every pinned digest in the shipped manifest is a sha-256', () {
      for (final reaction in kExtendedReactions) {
        expect(reaction.digest, matches(RegExp(r'^[0-9a-f]{64}$')), reason: reaction.emoji);
        expect(reaction.cdnUrl, contains(reaction.codepoint));
      }
    });
  });
}

class SocketFailure implements Exception {
  const SocketFailure();
}
