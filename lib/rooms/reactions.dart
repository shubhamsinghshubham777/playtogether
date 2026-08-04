class PTReaction {
  const PTReaction({
    required this.emoji,
    required this.codepoint,
    required this.label,
    this.digest,
  });

  final String emoji;
  final String codepoint;
  final String label;

  final String? digest;

  bool get isBundled => digest == null;

  String get asset => 'assets/emoji/$codepoint.json';

  String get cdnUrl => 'https://fonts.gstatic.com/s/e/notoemoji/latest/$codepoint/lottie.json';
}

const kReactions = <PTReaction>[
  PTReaction(emoji: '💖', codepoint: '1f496', label: 'Love it'),
  PTReaction(emoji: '👍', codepoint: '1f44d', label: 'Nice'),
  PTReaction(emoji: '🎉', codepoint: '1f389', label: 'Party'),
  PTReaction(emoji: '👏', codepoint: '1f44f', label: 'Applause'),
  PTReaction(emoji: '😂', codepoint: '1f602', label: 'Hilarious'),
  PTReaction(emoji: '😮', codepoint: '1f62e', label: 'Whoa'),
  PTReaction(emoji: '😢', codepoint: '1f622', label: 'Sad'),
  PTReaction(emoji: '🤔', codepoint: '1f914', label: 'Hmm'),
];

const kExtendedReactions = <PTReaction>[
  PTReaction(
    emoji: '🔥',
    codepoint: '1f525',
    label: 'Fire',
    digest: '96199d8e8fea7d90196b95b9a9e56b13af43e3817efe037bd9aa1e5215579838',
  ),
  PTReaction(
    emoji: '🍿',
    codepoint: '1f37f',
    label: 'Popcorn',
    digest: '8b48509721cf83b98946126f789178a289df6a67eef65690849ce0beec03d7a9',
  ),
  PTReaction(
    emoji: '🤣',
    codepoint: '1f923',
    label: 'Rolling',
    digest: 'da5832ec41e5b4b60a2668891bd0670c1495022096839b0b92d943cb85008aea',
  ),
  PTReaction(
    emoji: '😍',
    codepoint: '1f60d',
    label: 'Smitten',
    digest: '2351f649844d0211f0935346c6358b7cdd38e7f2fb42164b7ecedbb67f7954aa',
  ),
  PTReaction(
    emoji: '🤯',
    codepoint: '1f92f',
    label: 'Mind blown',
    digest: '553f0131420995a5f7d989fa3e243ce57fe2620a34e4866c2adf1dd000aeeecf',
  ),
  PTReaction(
    emoji: '😱',
    codepoint: '1f631',
    label: 'Scream',
    digest: '159c6e05378b35fdb834c8981893162aad7935c3c7f52db5070caa0f47aca925',
  ),
  PTReaction(
    emoji: '🥳',
    codepoint: '1f973',
    label: 'Celebrate',
    digest: '6cc02b10d9471287c26b188d5a9b64899da86543fde29b60ed5e5caf69776c3d',
  ),
  PTReaction(
    emoji: '🙌',
    codepoint: '1f64c',
    label: 'Hands up',
    digest: 'a7f2d88118d720d0d1b68496561f8ef57e3a4e47c354b2bbdd53608784228b3f',
  ),
  PTReaction(
    emoji: '💯',
    codepoint: '1f4af',
    label: 'Hundred',
    digest: '8e48b464d7473e94e7b744a1774f4c3b7c7a6892faee8667f9e555ddf5160798',
  ),
  PTReaction(
    emoji: '❤️',
    codepoint: '2764_fe0f',
    label: 'Heart',
    digest: '7925790edd7ec4a4da6ccb9491c61a2e03705182e7db263f12d8e46a8fcddb79',
  ),
  PTReaction(
    emoji: '👀',
    codepoint: '1f440',
    label: 'Watching',
    digest: '0dfcabf677099ebe20efacf98f680cf3aeac6f7b647228acda73917c65e2120f',
  ),
  PTReaction(
    emoji: '😭',
    codepoint: '1f62d',
    label: 'Sobbing',
    digest: '9f8b1a18099511d53356d870edd0e042323e0d2b023321ee144821e197f551ec',
  ),
  PTReaction(
    emoji: '💀',
    codepoint: '1f480',
    label: 'Dead',
    digest: 'e0ce80dfbd957fb9c64c432c1d16ca6123f290e270688b0e23601099bfc2cc31',
  ),
  PTReaction(
    emoji: '😴',
    codepoint: '1f634',
    label: 'Snooze',
    digest: '1fa14c30659503270104b54a7eefd082d7ebc039fc0bab280a6bd173fba3dcdd',
  ),
  PTReaction(
    emoji: '🤡',
    codepoint: '1f921',
    label: 'Clown',
    digest: '246c5aab976ccb17f5b7ef60ae27a1866d2a6f27bc082afc68923a55a7d83bcc',
  ),
  PTReaction(
    emoji: '🫠',
    codepoint: '1fae0',
    label: 'Melting',
    digest: '5d071c234038ddf15f6e14d3c40ab1b965dc3af4661f2c77c0ba41fc4d712e5c',
  ),
];

const kAllReactions = <PTReaction>[...kReactions, ...kExtendedReactions];

final _byEmoji = {for (final reaction in kAllReactions) reaction.emoji: reaction};

PTReaction? reactionForEmoji(String? emoji) => emoji == null ? null : _byEmoji[emoji];

const kBaseReactionCount = 8;

List<PTReaction> reactionsForTier(String? tier) =>
    tier == 'premium' ? kAllReactions : kReactions.take(kBaseReactionCount).toList(growable: false);

bool reactionAllowedForTier(String? emoji, String? tier) =>
    emoji != null && reactionsForTier(tier).any((r) => r.emoji == emoji);
