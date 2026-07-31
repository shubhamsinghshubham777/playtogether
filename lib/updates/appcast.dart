import 'dart:math' as math;

final _versionInFeed = RegExp(
  r'sparkle:(?:shortVersionString|version)\s*=\s*"([^"]*)"'
  r'|<sparkle:(?:shortVersionString|version)\s*>([^<]*)<',
);

String? newestVersionIn(String appcastXml) {
  String? best;
  for (final match in _versionInFeed.allMatches(appcastXml)) {
    final raw = (match.group(1) ?? match.group(2) ?? '').trim();
    if (raw.isEmpty) continue;
    if (best == null || compareVersions(raw, best) > 0) best = raw;
  }
  return best;
}

int compareVersions(String a, String b) {
  final left = _segments(a);
  final right = _segments(b);
  for (var i = 0; i < math.max(left.length, right.length); i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

List<int> _segments(String version) => version
    .trim()
    .split('+')
    .first
    .split('-')
    .first
    .split('.')
    .map((segment) => int.tryParse(segment.trim()) ?? 0)
    .toList();
