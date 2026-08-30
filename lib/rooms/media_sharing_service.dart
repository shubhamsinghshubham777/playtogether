import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/rooms/local_media_store.dart';
import 'package:synctogether/sync/sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class MediaSharingException implements Exception {
  final String code;
  final String message;
  final int? usedBytes;
  final int? weeklyLimitBytes;
  final DateTime? resetsAt;

  const MediaSharingException({
    required this.code,
    required this.message,
    this.usedBytes,
    this.weeklyLimitBytes,
    this.resetsAt,
  });

  factory MediaSharingException.fromError(dynamic error) {
    if (error is MediaSharingException) return error;

    String? code;
    Map<String, dynamic>? detailsMap;

    if (error is FunctionException) {
      final details = error.details;
      if (details is Map) {
        detailsMap = details.cast<String, dynamic>();
        code = detailsMap['error']?.toString();
        if (detailsMap['details'] is Map) {
          detailsMap = (detailsMap['details'] as Map).cast<String, dynamic>();
          code = detailsMap['error']?.toString() ?? code;
        }
      } else if (details is String) {
        code = details;
      }
    } else if (error is HttpException) {
      code = error.message;
    } else if (error is Map) {
      detailsMap = error.cast<String, dynamic>();
      code = detailsMap['error']?.toString();
      if (detailsMap['details'] is Map) {
        detailsMap = (detailsMap['details'] as Map).cast<String, dynamic>();
        code = detailsMap['error']?.toString() ?? code;
      }
    }

    code ??= error.toString();

    if (code.contains('quota_exceeded') || code.contains('upload_quota_exceeded')) {
      final used = detailsMap?['used_bytes'] as num?;
      final limit = detailsMap?['weekly_limit'] as num?;
      final resets = detailsMap?['resets_at'] != null
          ? DateTime.tryParse(detailsMap!['resets_at'].toString())
          : null;

      String msg;
      if (used != null && limit != null) {
        final usedStr = Profile.formatBytes(used.toInt());
        final limitStr = Profile.formatBytes(limit.toInt());
        msg =
            'Weekly upload quota reached ($usedStr of $limitStr used). Upgrade to Premium for unlimited bandwidth.';
      } else {
        msg = 'Weekly upload quota reached. Upgrade to Premium for unlimited uploads.';
      }

      return MediaSharingException(
        code: 'quota_exceeded',
        message: msg,
        usedBytes: used?.toInt(),
        weeklyLimitBytes: limit?.toInt(),
        resetsAt: resets,
      );
    }

    if (code.contains('concurrent_upload_active')) {
      return const MediaSharingException(
        code: 'concurrent_upload_active',
        message:
            'Another upload is already in progress on your account. Please wait for it to finish or cancel it.',
      );
    }

    if (code.contains('file_too_large')) {
      return const MediaSharingException(
        code: 'file_too_large',
        message: 'This video exceeds the maximum file size limit for your plan.',
      );
    }

    if (code.contains('unsupported_tier') || code.contains('media_sharing_not_allowed')) {
      return const MediaSharingException(
        code: 'unsupported_tier',
        message: 'Media sharing is not available on your current plan.',
      );
    }

    if (code.contains('Upload cancelled') || code.contains('cancelled')) {
      return const MediaSharingException(code: 'cancelled', message: 'Upload was cancelled.');
    }

    return MediaSharingException(
      code: 'unknown',
      message: error is FunctionException && error.reasonPhrase != null
          ? 'Upload failed: ${error.reasonPhrase}'
          : (error is HttpException ? error.message : 'Upload failed. Please try again.'),
    );
  }

  @override
  String toString() => message;
}

class FileSlice {
  const FileSlice({required this.partNumber, required this.startOffset, required this.endOffset});

  final int partNumber;
  final int startOffset;
  final int endOffset; // Exclusive

  int get length => endOffset - startOffset;
}

class UploadProgress {
  const UploadProgress({
    required this.bytesUploaded,
    required this.totalBytes,
    required this.speedBps,
    required this.etaSeconds,
    required this.state,
  });

  final int bytesUploaded;
  final int totalBytes;
  final double speedBps;
  final int etaSeconds;
  final String state;

  double get fraction => totalBytes > 0 ? (bytesUploaded / totalBytes).clamp(0.0, 1.0) : 0.0;
}

class DownloadUrlResult {
  const DownloadUrlResult({
    required this.streamUrl,
    required this.fileName,
    required this.fileSize,
    required this.expiresInSeconds,
  });

  final Uri streamUrl;
  final String fileName;
  final int fileSize;
  final int expiresInSeconds;
}

class StagedUploadSession {
  const StagedUploadSession({
    required this.stagedId,
    required this.fileName,
    required this.fileSize,
    required this.uploadId,
    required this.r2Key,
    required this.totalParts,
    required this.partSizeBytes,
    this.completedParts = const {},
  });

  final String stagedId;
  final String fileName;
  final int fileSize;
  final String uploadId;
  final String r2Key;
  final int totalParts;
  final int partSizeBytes;
  final Map<int, String> completedParts;

  StagedUploadSession copyWith({Map<int, String>? completedParts}) {
    return StagedUploadSession(
      stagedId: stagedId,
      fileName: fileName,
      fileSize: fileSize,
      uploadId: uploadId,
      r2Key: r2Key,
      totalParts: totalParts,
      partSizeBytes: partSizeBytes,
      completedParts: completedParts ?? this.completedParts,
    );
  }
}

class CancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

typedef EdgeFunctionCaller =
    Future<Map<String, dynamic>> Function(String action, Map<String, dynamic> body);
typedef HttpClientFactory = HttpClient Function();

class MediaSharingService {
  MediaSharingService({
    LocalMediaStore? mediaStore,
    EdgeFunctionCaller? edgeFunctionCaller,
    HttpClientFactory? httpClientFactory,
  }) : _mediaStore = mediaStore ?? LocalMediaStore.instance,
       _edgeCaller = edgeFunctionCaller ?? _defaultEdgeCaller,
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const int kPartSizeBytes = 10 * 1024 * 1024; // 10 MB

  final LocalMediaStore _mediaStore;
  final EdgeFunctionCaller _edgeCaller;
  final HttpClientFactory _httpClientFactory;

  static Future<Map<String, dynamic>> _defaultEdgeCaller(
    String action,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'media-share',
        body: {'action': action, ...body},
      );
      if (response.status != 200) {
        throw MediaSharingException.fromError(response.data ?? response);
      }
      return (response.data as Map).cast<String, dynamic>();
    } catch (e) {
      if (e is MediaSharingException) rethrow;
      throw MediaSharingException.fromError(e);
    }
  }

  static List<FileSlice> calculateSlices({required int fileSize, required int partSizeBytes}) {
    if (fileSize <= 0) return const [];
    final slices = <FileSlice>[];
    int start = 0;
    int partNumber = 1;

    while (start < fileSize) {
      final end = min(start + partSizeBytes, fileSize);
      slices.add(FileSlice(partNumber: partNumber, startOffset: start, endOffset: end));
      start = end;
      partNumber++;
    }
    return slices;
  }

  static String sanitizeETag(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll('"', '').trim();
  }

  Future<UploadSession> uploadFile({
    required String roomId,
    required File file,
    void Function(UploadProgress progress)? onProgress,
    SyncService? syncService,
  }) async {
    final fileSize = await file.length();
    final fileName = p.basename(file.path);
    final contentType = lookupMimeType(file.path) ?? 'video/mp4';

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    final initiateData = await _edgeCaller('initiate', {
      'roomId': roomId,
      'fileName': fileName,
      'fileSize': fileSize,
      'contentType': contentType,
    });

    final uploadId = initiateData['uploadId'] as String;
    final r2Key = initiateData['r2Key'] as String;
    final partSizeBytes = (initiateData['partSizeBytes'] as num?)?.toInt() ?? kPartSizeBytes;
    final totalParts = (initiateData['totalParts'] as num?)?.toInt() ?? 1;

    var session = UploadSession(
      roomId: roomId,
      uploadId: uploadId,
      r2Key: r2Key,
      filePath: file.path,
      fileSize: fileSize,
      partSizeBytes: partSizeBytes,
      totalParts: totalParts,
      completedParts: const {},
    );

    await _mediaStore.saveUploadSession(roomId: roomId, session: session);

    return _executeUploadPipeline(
      session: session,
      file: file,
      onProgress: onProgress,
      syncService: syncService,
    );
  }

  Future<UploadSession> resumeUpload({
    required String roomId,
    required File file,
    void Function(UploadProgress progress)? onProgress,
    SyncService? syncService,
  }) async {
    final initialSession = await _mediaStore.loadUploadSession(roomId);
    if (initialSession == null) {
      return uploadFile(
        roomId: roomId,
        file: file,
        onProgress: onProgress,
        syncService: syncService,
      );
    }
    var session = initialSession;

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    try {
      final listData = await _edgeCaller('list-parts', {
        'roomId': roomId,
        'uploadId': session.uploadId,
        'r2Key': session.r2Key,
      });

      final parts = (listData['parts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final reconciled = Map<int, String>.from(session.completedParts);
      for (final p in parts) {
        final partNum = (p['partNumber'] as num).toInt();
        final etag = sanitizeETag(p['etag'] as String?);
        reconciled[partNum] = etag;
      }

      session = session.copyWith(completedParts: reconciled);
      await _mediaStore.saveUploadSession(roomId: roomId, session: session);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reconciling multipart parts for room $roomId');
    }

    return _executeUploadPipeline(
      session: session,
      file: file,
      onProgress: onProgress,
      syncService: syncService,
    );
  }

  Future<UploadSession> _executeUploadPipeline({
    required UploadSession session,
    required File file,
    void Function(UploadProgress progress)? onProgress,
    SyncService? syncService,
  }) async {
    final slices = calculateSlices(
      fileSize: session.fileSize,
      partSizeBytes: session.partSizeBytes,
    );

    final completed = Map<int, String>.from(session.completedParts);
    final pendingSlices = slices.where((s) => !completed.containsKey(s.partNumber)).toList();

    int totalUploadedBytes = completed.entries.fold(0, (sum, entry) {
      final slice = slices.firstWhere((s) => s.partNumber == entry.key);
      return sum + slice.length;
    });

    final stopwatch = Stopwatch()..start();
    int lastSampleBytes = totalUploadedBytes;
    int lastSampleMs = 0;
    double currentSpeedBps = 0;

    void reportProgress(String state) {
      final elapsedMs = stopwatch.elapsedMilliseconds;
      if (elapsedMs - lastSampleMs >= 500 || totalUploadedBytes >= session.fileSize) {
        final deltaBytes = totalUploadedBytes - lastSampleBytes;
        final deltaTime = (elapsedMs - lastSampleMs) / 1000.0;
        currentSpeedBps = deltaTime > 0 ? (deltaBytes / deltaTime) : 0;
        lastSampleBytes = totalUploadedBytes;
        lastSampleMs = elapsedMs;
      }

      final remainingBytes = session.fileSize - totalUploadedBytes;
      final etaSeconds = currentSpeedBps > 0 ? (remainingBytes / currentSpeedBps).ceil() : 0;
      final fraction = session.fileSize > 0
          ? (totalUploadedBytes / session.fileSize).clamp(0.0, 1.0)
          : 0.0;

      final p = UploadProgress(
        bytesUploaded: totalUploadedBytes,
        totalBytes: session.fileSize,
        speedBps: currentSpeedBps,
        etaSeconds: etaSeconds,
        state: state,
      );

      onProgress?.call(p);
      syncService?.broadcastUploadProgress(
        fraction: fraction,
        speedBps: currentSpeedBps,
        etaSeconds: etaSeconds,
        state: state,
      );
    }

    reportProgress('uploading');

    // Process slices in sliding window of 5
    const windowSize = 5;
    for (int i = 0; i < pendingSlices.length; i += windowSize) {
      final batch = pendingSlices.sublist(i, min(i + windowSize, pendingSlices.length));
      final partNumbers = batch.map((s) => s.partNumber).toList();

      final urlData = await _edgeCaller('part-urls', {
        'roomId': session.roomId,
        'uploadId': session.uploadId,
        'r2Key': session.r2Key,
        'partNumbers': partNumbers,
      });

      final partsWithUrls = (urlData['parts'] as List).cast<Map<String, dynamic>>();
      final urlMap = {
        for (final p in partsWithUrls) (p['partNumber'] as num).toInt(): p['url'] as String,
      };

      for (final slice in batch) {
        final presignedUrl = Uri.parse(urlMap[slice.partNumber]!);
        final client = _httpClientFactory();

        try {
          final request = await client.putUrl(presignedUrl);
          request.contentLength = slice.length;

          final stream = file.openRead(slice.startOffset, slice.endOffset);
          await request.addStream(stream);

          final response = await request.close().timeout(const Duration(seconds: 60));
          if (response.statusCode != HttpStatus.ok) {
            throw HttpException('S3 part upload failed with HTTP ${response.statusCode}');
          }

          final etag = sanitizeETag(response.headers.value(HttpHeaders.etagHeader));
          if (etag.isEmpty) {
            throw const HttpException('Missing ETag in part upload response');
          }

          completed[slice.partNumber] = etag;
          totalUploadedBytes += slice.length;

          session = session.copyWith(completedParts: completed);
          await _mediaStore.saveUploadSession(roomId: session.roomId, session: session);

          reportProgress('uploading');
        } finally {
          client.close();
        }
      }
    }

    // Complete upload: sort parts strictly ascending by partNumber
    final sortedParts = completed.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    await _edgeCaller('complete', {
      'roomId': session.roomId,
      'uploadId': session.uploadId,
      'r2Key': session.r2Key,
      'fileSize': session.fileSize,
      'parts': sortedParts.map((e) => {'partNumber': e.key, 'etag': e.value}).toList(),
    });

    await _mediaStore.clearUploadSession(session.roomId);
    reportProgress('ready');

    try {
      await WakelockPlus.disable();
    } catch (_) {}

    return session;
  }

  Future<void> abortUpload({required String roomId, int bytesUploaded = 0}) async {
    final session = await _mediaStore.loadUploadSession(roomId);
    try {
      await _edgeCaller('abort', {
        'roomId': roomId,
        'uploadId': session?.uploadId,
        'r2Key': session?.r2Key,
        'bytesUploaded': bytesUploaded,
      });
    } catch (e, s) {
      reportNonFatal(e, s, during: 'aborting upload for room $roomId');
    } finally {
      await _mediaStore.clearUploadSession(roomId);
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  Future<DownloadUrlResult> fetchDownloadUrl({required String roomId}) async {
    final data = await _edgeCaller('download-url', {'roomId': roomId});
    return DownloadUrlResult(
      streamUrl: Uri.parse(data['streamUrl'] as String),
      fileName: data['fileName'] as String? ?? 'video.mp4',
      fileSize: (data['fileSize'] as num?)?.toInt() ?? 0,
      expiresInSeconds: (data['expiresIn'] as num?)?.toInt() ?? 3600,
    );
  }

  Future<StagedUploadSession> uploadStagedFile({
    required File file,
    Duration? duration,
    void Function(UploadProgress)? onProgress,
    void Function(StagedUploadSession session)? onSessionCreated,
    CancellationToken? cancelToken,
  }) async {
    final fileName = p.basename(file.path);
    final fileSize = await file.length();
    final mime = lookupMimeType(file.path) ?? 'video/mp4';

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    final initiateData = await _edgeCaller('staged-initiate', {
      'fileName': fileName,
      'fileSize': fileSize,
      'durationMs': duration?.inMilliseconds,
      'contentType': mime,
    });

    final stagedId = initiateData['stagedId'] as String;
    final uploadId = initiateData['uploadId'] as String;
    final r2Key = initiateData['r2Key'] as String;
    final partSize = (initiateData['partSizeBytes'] as num?)?.toInt() ?? kPartSizeBytes;

    final slices = calculateSlices(fileSize: fileSize, partSizeBytes: partSize);
    var session = StagedUploadSession(
      stagedId: stagedId,
      fileName: fileName,
      fileSize: fileSize,
      uploadId: uploadId,
      r2Key: r2Key,
      totalParts: slices.length,
      partSizeBytes: partSize,
      completedParts: {},
    );

    onSessionCreated?.call(session);

    int totalUploadedBytes = 0;
    int uploadStartTime = DateTime.now().millisecondsSinceEpoch;
    double currentSpeedBps = 0.0;
    int etaSeconds = 0;

    void reportProgress(String state) {
      final elapsedSec = max(
        0.001,
        (DateTime.now().millisecondsSinceEpoch - uploadStartTime) / 1000.0,
      );
      currentSpeedBps = totalUploadedBytes / elapsedSec;
      final remainingBytes = max(0, fileSize - totalUploadedBytes);
      etaSeconds = currentSpeedBps > 0 ? (remainingBytes / currentSpeedBps).ceil() : 0;

      final p = UploadProgress(
        bytesUploaded: totalUploadedBytes,
        totalBytes: fileSize,
        speedBps: currentSpeedBps,
        etaSeconds: etaSeconds,
        state: state,
      );

      onProgress?.call(p);
    }

    reportProgress('uploading');

    final completed = <int, String>{};
    const windowSize = 5;

    try {
      for (int i = 0; i < slices.length; i += windowSize) {
        if (cancelToken?.isCancelled ?? false) {
          throw const HttpException('Upload cancelled');
        }

        final batch = slices.sublist(i, min(i + windowSize, slices.length));
        final partNumbers = batch.map((s) => s.partNumber).toList();

        final urlData = await _edgeCaller('staged-part-urls', {
          'stagedId': stagedId,
          'uploadId': uploadId,
          'r2Key': r2Key,
          'partNumbers': partNumbers,
        });

        final partsWithUrls = (urlData['parts'] as List).cast<Map<String, dynamic>>();
        final urlMap = {
          for (final p in partsWithUrls) (p['partNumber'] as num).toInt(): p['url'] as String,
        };

        for (final slice in batch) {
          if (cancelToken?.isCancelled ?? false) {
            throw const HttpException('Upload cancelled');
          }

          final presignedUrl = Uri.parse(urlMap[slice.partNumber]!);
          final client = _httpClientFactory();

          try {
            final request = await client.putUrl(presignedUrl);
            request.contentLength = slice.length;

            final stream = file.openRead(slice.startOffset, slice.endOffset);
            await request.addStream(stream);

            final response = await request.close().timeout(const Duration(seconds: 60));
            if (response.statusCode != HttpStatus.ok) {
              throw HttpException('S3 part upload failed with HTTP ${response.statusCode}');
            }

            final etag = sanitizeETag(response.headers.value(HttpHeaders.etagHeader));
            if (etag.isEmpty) {
              throw const HttpException('Missing ETag in part upload response');
            }

            completed[slice.partNumber] = etag;
            totalUploadedBytes += slice.length;

            session = session.copyWith(completedParts: completed);
            reportProgress('uploading');
          } finally {
            client.close();
          }
        }
      }

      final sortedParts = completed.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

      await _edgeCaller('staged-complete', {
        'stagedId': stagedId,
        'uploadId': uploadId,
        'r2Key': r2Key,
        'fileSize': fileSize,
        'parts': sortedParts.map((e) => {'partNumber': e.key, 'etag': e.value}).toList(),
      });

      reportProgress('ready');
      return session;
    } catch (e) {
      // Auto-abort staged upload on cancellation or error to release DB lock immediately
      try {
        await abortStagedUpload(
          stagedId: stagedId,
          uploadId: uploadId,
          r2Key: r2Key,
          bytesUploaded: totalUploadedBytes,
        );
      } catch (_) {}
      rethrow;
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  Future<void> abortStagedUpload({
    required String stagedId,
    required String uploadId,
    required String r2Key,
    int bytesUploaded = 0,
  }) async {
    try {
      await _edgeCaller('staged-abort', {
        'stagedId': stagedId,
        'uploadId': uploadId,
        'r2Key': r2Key,
        'bytesUploaded': bytesUploaded,
      });
    } catch (e, s) {
      reportNonFatal(e, s, during: 'aborting staged upload $stagedId');
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }
}
