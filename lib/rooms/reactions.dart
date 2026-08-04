class PTReaction {
  const PTReaction({required this.emoji, required this.codepoint, required this.label});

  final String emoji;
  final String codepoint;
  final String label;

  String get asset => 'assets/emoji/$codepoint.json';
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

final _byEmoji = {for (final reaction in kReactions) reaction.emoji: reaction};

PTReaction? reactionForEmoji(String? emoji) => emoji == null ? null : _byEmoji[emoji];

const kBaseReactionCount = 8;

List<PTReaction> reactionsForTier(String? tier) => kReactions
    .take(tier == 'premium' ? kReactions.length : kBaseReactionCount)
    .toList(growable: false);

bool reactionAllowedForTier(String? emoji, String? tier) =>
    emoji != null && reactionsForTier(tier).any((r) => r.emoji == emoji);
