import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/rooms/reactions.dart';

final _root = Directory.current;

File _repoFile(String relative) => File('${_root.path}/$relative');

void main() {
  group('kReactions', () {
    test('is non-empty and has unique emoji, codepoints and labels', () {
      expect(kReactions, isNotEmpty);
      expect(kReactions.map((r) => r.emoji).toSet().length, kReactions.length);
      expect(kReactions.map((r) => r.codepoint).toSet().length, kReactions.length);
      expect(kReactions.map((r) => r.label).toSet().length, kReactions.length);
    });

    test('every codepoint is lowercase hex, matching the fetch script regex', () {
      for (final reaction in kReactions) {
        expect(
          RegExp(r'^[0-9a-f]+$').hasMatch(reaction.codepoint),
          isTrue,
          reason: reaction.codepoint,
        );
      }
    });

    test('every codepoint is the actual codepoint of its glyph', () {
      for (final reaction in kReactions) {
        final runes = reaction.emoji.runes.toList();
        expect(runes.length, 1, reason: '${reaction.emoji} is not a single rune');
        expect(
          runes.single.toRadixString(16),
          reaction.codepoint,
          reason: '${reaction.emoji} is paired with the wrong asset codepoint',
        );
      }
    });

    test('asset paths point into the bundled emoji directory', () {
      for (final reaction in kReactions) {
        expect(reaction.asset, 'assets/emoji/${reaction.codepoint}.json');
      }
    });
  });

  group('bundled assets', () {
    test('every reaction has a bundled Lottie file on disk', () {
      for (final reaction in kReactions) {
        expect(
          _repoFile(reaction.asset).existsSync(),
          isTrue,
          reason: '${reaction.asset} is missing — run tool/fetch_reaction_emoji.py',
        );
      }
    });

    test('the emoji directory holds no orphans the allow-list would never render', () {
      final onDisk = Directory('${_root.path}/assets/emoji')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
          .toSet();
      expect(onDisk, kReactions.map((r) => r.codepoint).toSet());
    });

    test('each bundled file is a usable Lottie document', () {
      for (final reaction in kReactions) {
        final raw = _repoFile(reaction.asset).readAsStringSync();
        final doc = jsonDecode(raw) as Map<String, dynamic>;
        expect(doc['layers'], isNotEmpty, reason: reaction.asset);
        expect(doc['op'], isNotNull, reason: reaction.asset);
        expect(doc['fr'], isNotNull, reason: reaction.asset);
      }
    });

    test('pubspec ships the emoji directory as an asset', () {
      final pubspec = _repoFile('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/emoji/'));
    });
  });

  group('agreement with tool/fetch_reaction_emoji.py', () {
    late Map<String, String> glyphs;
    late Map<String, String> digests;

    setUpAll(() {
      final source = _repoFile('tool/fetch_reaction_emoji.py').readAsStringSync();
      final entries = RegExp(
        r'\(\s*"([0-9a-f_]+)"\s*,\s*"(\S+?)"\s*,\s*"([0-9a-f]{64})"\s*\)',
      ).allMatches(source);
      glyphs = {for (final m in entries) m.group(1)!: m.group(2)!};
      digests = {for (final m in entries) m.group(1)!: m.group(3)!};
    });

    test('the manifest was parsed at all, so this check cannot silently pass', () {
      expect(
        glyphs,
        isNotEmpty,
        reason: 'the EMOJI tables were restructured — this check needs restructuring with it',
      );
    });

    test('the codepoint sets agree in both directions', () {
      expect(glyphs.keys.toSet(), kAllReactions.map((r) => r.codepoint).toSet());
    });

    test('each codepoint is paired with the same glyph in both places', () {
      for (final reaction in kAllReactions) {
        expect(
          glyphs[reaction.codepoint],
          reaction.emoji,
          reason: 'the script fetches ${reaction.codepoint} for a different glyph',
        );
      }
    });

    test('the extended digests match the ones the runtime fetch checks against', () {
      for (final reaction in kExtendedReactions) {
        expect(
          reaction.digest,
          digests[reaction.codepoint],
          reason:
              'the app would verify ${reaction.codepoint} against a digest the script '
              'never confirmed the CDN serves',
        );
      }
    });
  });

  group('reactionForEmoji', () {
    test('resolves every listed emoji to its own entry', () {
      for (final reaction in kAllReactions) {
        final found = reactionForEmoji(reaction.emoji);
        expect(found, isNotNull, reason: reaction.emoji);
        expect(found!.codepoint, reaction.codepoint);
        expect(found.label, reaction.label);
      }
    });

    test('rejects an emoji outside the manifest, which we have no way to render', () {
      expect(reactionForEmoji('🦆'), isNull);
      expect(reactionForEmoji('💩'), isNull);
      expect(reactionForEmoji('🧀'), isNull);
    });

    test('accepts the extended set too, so a free viewer sees a premium sender', () {
      for (final reaction in kExtendedReactions) {
        expect(reactionForEmoji(reaction.emoji), isNotNull, reason: reaction.emoji);
      }
    });

    test('rejects null and empty, which is what an untrusted payload decodes to', () {
      expect(reactionForEmoji(null), isNull);
      expect(reactionForEmoji(''), isNull);
    });

    test('rejects non-emoji text a peer could put in the field', () {
      expect(reactionForEmoji('play'), isNull);
      expect(reactionForEmoji('<script>'), isNull);
      expect(reactionForEmoji('1f496'), isNull);
    });

    test('matches exactly, so a variation-selector suffix is rejected', () {
      for (final reaction in kReactions) {
        expect(reactionForEmoji('${reaction.emoji}️'), isNull, reason: reaction.emoji);
      }
    });

    test('rejects a run of two otherwise-valid emoji', () {
      expect(reactionForEmoji('${kReactions.first.emoji}${kReactions.last.emoji}'), isNull);
    });
  });

  group('tier gating on the send path', () {
    test('everyone below premium sends the bundled set', () {
      expect(reactionsForTier('guest'), kReactions);
      expect(reactionsForTier('free'), kReactions);
      expect(reactionsForTier(null), kReactions);
    });

    test('premium sends the whole manifest', () {
      expect(reactionsForTier('premium'), kAllReactions);
      expect(reactionsForTier('premium').length, greaterThan(kBaseReactionCount));
    });

    test('a bundled emoji is allowed for any tier', () {
      for (final reaction in kReactions) {
        expect(reactionAllowedForTier(reaction.emoji, 'free'), isTrue, reason: reaction.emoji);
        expect(reactionAllowedForTier(reaction.emoji, null), isTrue, reason: reaction.emoji);
      }
    });

    test('the extended set is premium to send, even though anyone can see it', () {
      for (final reaction in kExtendedReactions) {
        expect(reactionAllowedForTier(reaction.emoji, 'free'), isFalse, reason: reaction.emoji);
        expect(reactionAllowedForTier(reaction.emoji, 'premium'), isTrue, reason: reaction.emoji);
        expect(reactionForEmoji(reaction.emoji), isNotNull, reason: reaction.emoji);
      }
    });

    test('an emoji outside the manifest is refused whatever the tier', () {
      expect(reactionAllowedForTier('🦄', 'premium'), isFalse);
      expect(reactionAllowedForTier(null, 'premium'), isFalse);
      expect(reactionAllowedForTier('', 'premium'), isFalse);
    });

    test('the base set is never larger than what ships', () {
      expect(kBaseReactionCount, lessThanOrEqualTo(kReactions.length));
    });

    test('the manifest has no duplicate emoji or codepoints', () {
      expect(kAllReactions.map((r) => r.emoji).toSet().length, kAllReactions.length);
      expect(kAllReactions.map((r) => r.codepoint).toSet().length, kAllReactions.length);
    });

    test('the bundled set carries no digest, the extended set always does', () {
      for (final reaction in kReactions) {
        expect(reaction.isBundled, isTrue, reason: reaction.emoji);
      }
      for (final reaction in kExtendedReactions) {
        expect(reaction.isBundled, isFalse, reason: reaction.emoji);
        expect(reaction.digest, hasLength(64), reason: reaction.emoji);
      }
    });
  });
}
