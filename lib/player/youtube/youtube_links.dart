typedef MessageSegment = ({String text, String? videoId});

final _videoIdPattern = RegExp(r'^[\w-]{11}$');

final _hostAliasPattern = RegExp(r'^(?:www|m|music)\.');

final _linkPattern = RegExp(
  r'(?<![\w.\-/])(?:https?://)?(?:[\w-]+\.)*'
  r'(?:youtube\.com|youtube-nocookie\.com|youtu\.be)/\S*',
  caseSensitive: false,
);

final _trailingPunctuationPattern = RegExp(r'''[.,;:!?)\]}>'"]+$''');

String? youtubeVideoId(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst(_hostAliasPattern, '');
  final path = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  final String? id;
  if (host == 'youtu.be') {
    id = path.firstOrNull;
  } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
    id = switch (path.firstOrNull) {
      'watch' => uri.queryParameters['v'],
      'embed' || 'shorts' || 'live' || 'v' => path.elementAtOrNull(1),
      _ => null,
    };
  } else {
    id = null;
  }
  if (id == null || !_videoIdPattern.hasMatch(id)) return null;
  return id;
}

String canonicalYouTubeUrl(String videoId) => 'https://www.youtube.com/watch?v=$videoId';

String youtubeThumbnailUrl(String videoId) => 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

List<MessageSegment> splitYouTubeLinks(String text) {
  final segments = <MessageSegment>[];
  var cursor = 0;
  for (final match in _linkPattern.allMatches(text)) {
    if (match.start < cursor) continue;
    final matched = match.group(0)!;
    final stripped = matched.replaceFirst(_trailingPunctuationPattern, '');
    final link = youtubeVideoId(stripped) != null ? stripped : matched;
    final videoId = youtubeVideoId(link);
    if (videoId == null) continue;
    if (match.start > cursor) {
      segments.add((text: text.substring(cursor, match.start), videoId: null));
    }
    segments.add((text: link, videoId: videoId));
    cursor = match.start + link.length;
  }
  if (cursor < text.length) {
    segments.add((text: text.substring(cursor), videoId: null));
  }
  return segments;
}
