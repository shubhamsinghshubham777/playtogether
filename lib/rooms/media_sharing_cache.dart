import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:storage_space/storage_space.dart';

class CacheProgress {
  const CacheProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.speedBps,
    required this.etaSeconds,
  });

  final int bytesReceived;
  final int totalBytes;
  final double speedBps;
  final int etaSeconds;

  double get fraction => totalBytes > 0 ? (bytesReceived / totalBytes).clamp(0.0, 1.0) : 0.0;
}

class MediaSharingCache {
  MediaSharingCache({Directory? cacheDirectory}) : _cacheDir = cacheDirectory;

  Directory? _cacheDir;

  Future<Directory> get cacheDirectory async {
    if (_cacheDir != null) {
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      return _cacheDir!;
    }
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'media_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  String getCacheFilePath(String r2Key) {
    final hash = sha256.convert(utf8.encode(r2Key)).toString();
    final ext = p.extension(r2Key).toLowerCase();
    final safeExt = ext.isNotEmpty ? ext : '.mp4';
    final dirPath = _cacheDir?.path ?? '';
    return dirPath.isNotEmpty ? p.join(dirPath, '$hash$safeExt') : '$hash$safeExt';
  }

  Future<String> getResolvedCacheFilePath(String r2Key) async {
    final dir = await cacheDirectory;
    final hash = sha256.convert(utf8.encode(r2Key)).toString();
    final ext = p.extension(r2Key).toLowerCase();
    final safeExt = ext.isNotEmpty ? ext : '.mp4';
    return p.join(dir.path, '$hash$safeExt');
  }

  Future<bool> isCached(String r2Key) async {
    final path = _cacheDir != null
        ? getCacheFilePath(r2Key)
        : await getResolvedCacheFilePath(r2Key);
    final file = File(path);
    return file.exists();
  }

  Future<void> evict(String r2Key) async {
    final path = _cacheDir != null
        ? getCacheFilePath(r2Key)
        : await getResolvedCacheFilePath(r2Key);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> hasEnoughSpace(int requiredBytes) async {
    try {
      final space = await getStorageSpace(
        lowOnSpaceThreshold: 100 * 1024 * 1024,
        fractionDigits: 1,
      );
      return space.free >= requiredBytes + (200 * 1024 * 1024); // 200 MB buffer
    } catch (_) {
      return true; // Fallback if platform check is unavailable
    }
  }

  Future<File> downloadFile({
    required String r2Key,
    required Uri downloadUrl,
    required int totalBytes,
    void Function(CacheProgress progress)? onProgress,
    HttpClient? httpClient,
  }) async {
    final finalPath = await getResolvedCacheFilePath(r2Key);
    final finalFile = File(finalPath);
    if (await finalFile.exists()) {
      onProgress?.call(
        CacheProgress(
          bytesReceived: totalBytes,
          totalBytes: totalBytes,
          speedBps: 0,
          etaSeconds: 0,
        ),
      );
      return finalFile;
    }

    final tempPath = '$finalPath.tmp';
    final tempFile = File(tempPath);

    int existingBytes = 0;
    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
      if (existingBytes >= totalBytes) {
        await tempFile.rename(finalPath);
        return finalFile;
      }
    }

    final client = httpClient ?? HttpClient();
    final request = await client.getUrl(downloadUrl);
    if (existingBytes > 0) {
      request.headers.add(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
    }

    final response = await request.close();
    if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
      throw HttpException('Failed to download media: HTTP ${response.statusCode}');
    }

    final sink = tempFile.openWrite(mode: existingBytes > 0 ? FileMode.append : FileMode.write);
    int receivedBytes = existingBytes;

    final stopwatch = Stopwatch()..start();
    int lastSampleBytes = receivedBytes;
    int lastSampleMs = 0;
    double currentSpeedBps = 0;

    await for (final chunk in response) {
      sink.add(chunk);
      receivedBytes += chunk.length;

      final elapsedMs = stopwatch.elapsedMilliseconds;
      if (elapsedMs - lastSampleMs >= 500) {
        final deltaBytes = receivedBytes - lastSampleBytes;
        final deltaTime = (elapsedMs - lastSampleMs) / 1000.0;
        currentSpeedBps = deltaTime > 0 ? (deltaBytes / deltaTime) : 0;
        lastSampleBytes = receivedBytes;
        lastSampleMs = elapsedMs;

        final remainingBytes = totalBytes - receivedBytes;
        final etaSeconds = currentSpeedBps > 0 ? (remainingBytes / currentSpeedBps).ceil() : 0;

        onProgress?.call(
          CacheProgress(
            bytesReceived: receivedBytes,
            totalBytes: totalBytes,
            speedBps: currentSpeedBps,
            etaSeconds: etaSeconds,
          ),
        );
      }
    }

    await sink.flush();
    await sink.close();

    if (httpClient == null) {
      client.close();
    }

    await tempFile.rename(finalPath);
    onProgress?.call(
      CacheProgress(
        bytesReceived: totalBytes,
        totalBytes: totalBytes,
        speedBps: currentSpeedBps,
        etaSeconds: 0,
      ),
    );

    return finalFile;
  }

  Future<void> cleanOrphanedTempFiles() async {
    final dir = await cacheDirectory;
    if (!await dir.exists()) return;

    final entries = dir.listSync();
    for (final entity in entries) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> pruneOldEntries({Duration maxAge = const Duration(days: 7)}) async {
    final dir = await cacheDirectory;
    if (!await dir.exists()) return;

    final cutoff = DateTime.now().subtract(maxAge);
    final entries = dir.listSync();
    for (final entity in entries) {
      if (entity is File && !entity.path.endsWith('.tmp')) {
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        } catch (_) {}
      }
    }
  }
}
