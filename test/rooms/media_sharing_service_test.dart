import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:playtogether/rooms/media_sharing_service.dart';

void main() {
  group('MediaSharingService', () {
    test('calculateSlices slices file properly', () {
      final slices = MediaSharingService.calculateSlices(
        fileSize: 25 * 1024 * 1024,
        partSizeBytes: 10 * 1024 * 1024,
      );
      expect(slices.length, 3);
      expect(slices[0].partNumber, 1);
      expect(slices[0].startOffset, 0);
      expect(slices[0].endOffset, 10 * 1024 * 1024);
      expect(slices[0].length, 10 * 1024 * 1024);

      expect(slices[1].partNumber, 2);
      expect(slices[1].startOffset, 10 * 1024 * 1024);
      expect(slices[1].endOffset, 20 * 1024 * 1024);

      expect(slices[2].partNumber, 3);
      expect(slices[2].startOffset, 20 * 1024 * 1024);
      expect(slices[2].endOffset, 25 * 1024 * 1024);
      expect(slices[2].length, 5 * 1024 * 1024);
    });

    test('calculateSlices handles empty or zero size file', () {
      final slices = MediaSharingService.calculateSlices(
        fileSize: 0,
        partSizeBytes: 10 * 1024 * 1024,
      );
      expect(slices, isEmpty);
    });

    test('uploadStagedFile orchestrates staged initiate, parts, and complete', () async {
      final calledActions = <String>[];
      final tempDir = await Directory.systemTemp.createTemp('pt_test');
      final testFile = File('${tempDir.path}/test_movie.mp4');
      await testFile.writeAsBytes(List.filled(1024, 65));

      final service = MediaSharingService(
        edgeFunctionCaller: (action, body) async {
          calledActions.add(action);
          if (action == 'staged-initiate') {
            return {
              'stagedId': 'staged-uuid-1',
              'uploadId': 'upload-uuid-1',
              'r2Key': 'users/u1/staged/test.mp4',
              'partSizeBytes': 10 * 1024 * 1024,
              'totalParts': 1,
            };
          } else if (action == 'staged-part-urls') {
            return {
              'parts': [
                {'partNumber': 1, 'url': 'http://localhost/part1'},
              ],
            };
          } else if (action == 'staged-complete') {
            return {'success': true, 'stagedId': 'staged-uuid-1', 'state': 'ready'};
          }
          return {};
        },
        httpClientFactory: () {
          return _MockHttpClient();
        },
      );

      final progressEvents = <UploadProgress>[];
      final session = await service.uploadStagedFile(
        file: testFile,
        onProgress: (p) => progressEvents.add(p),
      );

      expect(session.stagedId, 'staged-uuid-1');
      expect(session.uploadId, 'upload-uuid-1');
      expect(session.r2Key, 'users/u1/staged/test.mp4');
      expect(session.completedParts[1], 'mock-etag-1');
      expect(
        calledActions,
        containsAll(['staged-initiate', 'staged-part-urls', 'staged-complete']),
      );
      expect(progressEvents.isNotEmpty, true);
      expect(progressEvents.last.state, 'ready');

      await tempDir.delete(recursive: true);
    });

    test('abortStagedUpload calls staged-abort with correct payload', () async {
      Map<String, dynamic>? abortBody;
      final service = MediaSharingService(
        edgeFunctionCaller: (action, body) async {
          if (action == 'staged-abort') {
            abortBody = body;
          }
          return {'success': true};
        },
      );

      await service.abortStagedUpload(
        stagedId: 'staged-123',
        uploadId: 'upload-456',
        r2Key: 'r2-key-789',
        bytesUploaded: 5000,
      );

      expect(abortBody, isNotNull);
      expect(abortBody!['stagedId'], 'staged-123');
      expect(abortBody!['uploadId'], 'upload-456');
      expect(abortBody!['r2Key'], 'r2-key-789');
      expect(abortBody!['bytesUploaded'], 5000);
    });

    test('uploadStagedFile auto-aborts when cancelToken is cancelled', () async {
      final calledActions = <String>[];
      final tempDir = await Directory.systemTemp.createTemp('pt_test');
      final testFile = File('${tempDir.path}/test_movie.mp4');
      await testFile.writeAsBytes(List.filled(1024, 65));

      final cancelToken = CancellationToken();
      final service = MediaSharingService(
        edgeFunctionCaller: (action, body) async {
          calledActions.add(action);
          if (action == 'staged-initiate') {
            return {
              'stagedId': 'staged-uuid-cancel',
              'uploadId': 'upload-uuid-cancel',
              'r2Key': 'users/u1/staged/cancel.mp4',
              'partSizeBytes': 10 * 1024 * 1024,
              'totalParts': 1,
            };
          } else if (action == 'staged-part-urls') {
            cancelToken.cancel(); // Cancel mid-flight
            return {
              'parts': [
                {'partNumber': 1, 'url': 'http://localhost/part1'},
              ],
            };
          } else if (action == 'staged-abort') {
            return {'success': true};
          }
          return {};
        },
        httpClientFactory: () => _MockHttpClient(),
      );

      StagedUploadSession? createdSession;
      await expectLater(
        () => service.uploadStagedFile(
          file: testFile,
          cancelToken: cancelToken,
          onSessionCreated: (s) => createdSession = s,
        ),
        throwsA(isA<HttpException>()),
      );

      expect(createdSession?.stagedId, 'staged-uuid-cancel');
      expect(calledActions, contains('staged-abort'));

      await tempDir.delete(recursive: true);
    });
  });
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> putUrl(Uri url) async {
    return _MockHttpClientRequest();
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  int contentLength = 0;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain();
  }

  @override
  Future<HttpClientResponse> close() async {
    return _MockHttpClientResponse();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  final HttpHeaders headers = _MockResponseHeaders();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockResponseHeaders implements HttpHeaders {
  @override
  String? value(String name) {
    if (name.toLowerCase() == 'etag') return '"mock-etag-1"';
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
