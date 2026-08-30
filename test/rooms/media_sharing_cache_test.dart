import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/media_sharing_cache.dart';

void main() {
  late Directory tempDir;
  late MediaSharingCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pt_cache_test_');
    cache = MediaSharingCache(cacheDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MediaSharingCache', () {
    test('getCacheFilePath produces deterministic safe file paths', () {
      final path1 = cache.getCacheFilePath('rooms/r1/movie.mp4');
      final path2 = cache.getCacheFilePath('rooms/r1/movie.mp4');
      final path3 = cache.getCacheFilePath('rooms/r2/movie.mp4');

      expect(path1, path2);
      expect(path1, isNot(path3));
      expect(path1.endsWith('.mp4'), isTrue);
    });

    test('isCached returns false for non-existent file and true when file exists', () async {
      const r2Key = 'rooms/r1/test.mp4';
      expect(await cache.isCached(r2Key), isFalse);

      final targetPath = cache.getCacheFilePath(r2Key);
      await File(targetPath).writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));

      expect(await cache.isCached(r2Key), isTrue);
    });

    test('evict removes specific cached key', () async {
      const r2Key = 'rooms/r1/test.mp4';
      final targetPath = cache.getCacheFilePath(r2Key);
      await File(targetPath).writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));

      expect(await cache.isCached(r2Key), isTrue);
      await cache.evict(r2Key);
      expect(await cache.isCached(r2Key), isFalse);
    });

    test('cleanOrphanedTempFiles removes old .tmp files', () async {
      final tmpFile = File('${tempDir.path}/orphan.tmp');
      await tmpFile.writeAsBytes(Uint8List.fromList([1, 2, 3]));
      expect(await tmpFile.exists(), isTrue);

      await cache.cleanOrphanedTempFiles();
      expect(await tmpFile.exists(), isFalse);
    });

    test('pruneOldEntries evicts files older than max age', () async {
      final oldFile = File('${tempDir.path}/old.mp4');
      await oldFile.writeAsBytes(Uint8List.fromList([1, 2, 3]));
      await oldFile.setLastModified(DateTime.now().subtract(const Duration(days: 8)));

      final freshFile = File('${tempDir.path}/fresh.mp4');
      await freshFile.writeAsBytes(Uint8List.fromList([4, 5, 6]));
      await freshFile.setLastModified(DateTime.now());

      await cache.pruneOldEntries(maxAge: const Duration(days: 7));

      expect(await oldFile.exists(), isFalse);
      expect(await freshFile.exists(), isTrue);
    });
  });
}
