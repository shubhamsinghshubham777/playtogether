import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/player/youtube/youtube_links.dart';

void main() {
  group('youtubeVideoId', () {
    test('accepts every shape the room can be pointed at', () {
      expect(youtubeVideoId('https://www.youtube.com/watch?v=J-95Mhipb98'), 'J-95Mhipb98');
      expect(youtubeVideoId('http://youtube.com/watch?v=J-95Mhipb98'), 'J-95Mhipb98');
      expect(youtubeVideoId('https://m.youtube.com/watch?v=J-95Mhipb98'), 'J-95Mhipb98');
      expect(youtubeVideoId('https://music.youtube.com/watch?v=J-95Mhipb98'), 'J-95Mhipb98');
      expect(youtubeVideoId('https://youtu.be/J-95Mhipb98'), 'J-95Mhipb98');
      expect(youtubeVideoId('https://www.youtube.com/embed/J-95Mhipb98'), 'J-95Mhipb98');
      expect(youtubeVideoId('https://www.youtube.com/shorts/J-95Mhipb98'), 'J-95Mhipb98');
      expect(youtubeVideoId('youtube.com/watch?v=J-95Mhipb98'), 'J-95Mhipb98');
      expect(youtubeVideoId('  https://youtu.be/J-95Mhipb98  '), 'J-95Mhipb98');
    });

    test('keeps the id when other query parameters ride along', () {
      expect(
        youtubeVideoId('https://www.youtube.com/watch?v=J-95Mhipb98&t=42s&list=PLabc'),
        'J-95Mhipb98',
      );
      expect(youtubeVideoId('https://youtu.be/J-95Mhipb98?t=42'), 'J-95Mhipb98');
    });

    test('rejects anything that is not actually a YouTube host', () {
      expect(youtubeVideoId('https://evil.com/?x=youtu.be/J-95Mhipb98'), isNull);
      expect(youtubeVideoId('https://notyoutube.com/watch?v=J-95Mhipb98'), isNull);
      expect(youtubeVideoId('https://www.youtube.com/watch?v=tooshort'), isNull);
      expect(youtubeVideoId('https://www.youtube.com/feed/subscriptions'), isNull);
      expect(youtubeVideoId('just some words'), isNull);
      expect(youtubeVideoId(''), isNull);
    });
  });

  group('splitYouTubeLinks', () {
    test('leaves a message with no link as a single plain run', () {
      final segments = splitYouTubeLinks('hey, are we starting soon?');
      expect(segments, hasLength(1));
      expect(segments.single.videoId, isNull);
      expect(segments.single.text, 'hey, are we starting soon?');
    });

    test('splits prose around the link it contains', () {
      const content =
          "hey! check out this video. let's play it: https://www.youtube.com/watch?v=J-95Mhipb98";
      final segments = splitYouTubeLinks(content);
      expect(segments, hasLength(2));
      expect(segments[0].videoId, isNull);
      expect(segments[0].text, "hey! check out this video. let's play it: ");
      expect(segments[1].videoId, 'J-95Mhipb98');
      expect(segments[1].text, 'https://www.youtube.com/watch?v=J-95Mhipb98');
      expect(segments.map((s) => s.text).join(), content);
    });

    test('keeps trailing prose and punctuation out of the link', () {
      const content = 'watch https://youtu.be/J-95Mhipb98, it is short!';
      final segments = splitYouTubeLinks(content);
      expect(segments.map((s) => s.text).join(), content);
      final link = segments.firstWhere((s) => s.videoId != null);
      expect(link.text, 'https://youtu.be/J-95Mhipb98');
      expect(link.videoId, 'J-95Mhipb98');
    });

    test('finds every link in a message with more than one', () {
      const content = 'this https://youtu.be/J-95Mhipb98 or this youtube.com/watch?v=dQw4w9WgXcQ ?';
      final segments = splitYouTubeLinks(content);
      expect(segments.map((s) => s.text).join(), content);
      expect(segments.map((s) => s.videoId).nonNulls, ['J-95Mhipb98', 'dQw4w9WgXcQ']);
    });

    test('ignores links to anywhere else', () {
      const content = 'read https://example.com/watch?v=J-95Mhipb98 first';
      final segments = splitYouTubeLinks(content);
      expect(segments, hasLength(1));
      expect(segments.single.videoId, isNull);
    });

    test('does not link a lookalike host', () {
      final segments = splitYouTubeLinks('go to notyoutube.com/watch?v=J-95Mhipb98 now');
      expect(segments.every((s) => s.videoId == null), isTrue);
    });
  });
}
