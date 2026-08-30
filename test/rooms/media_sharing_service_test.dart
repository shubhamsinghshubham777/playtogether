import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/local_media_store.dart';
import 'package:synctogether/rooms/media_sharing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockHttpClient implements HttpClient {
  _MockHttpClient([this.requestHandler]);

  final Future<HttpClientRequest> Function(Uri url, String method)? requestHandler;

  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => requestHandler != null
      ? requestHandler!(url, method)
      : Future.value(_MockHttpClientRequest());

  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      requestHandler != null ? requestHandler!(url, 'PUT') : Future.value(_MockHttpClientRequest());

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      requestHandler != null ? requestHandler!(url, 'GET') : Future.value(_MockHttpClientRequest());

  @override
  Future<HttpClientRequest> postUrl(Uri url) => requestHandler != null
      ? requestHandler!(url, 'POST')
      : Future.value(_MockHttpClientRequest());

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  _MockHttpClientRequest({Uri? uri, this.method = 'PUT', this.responseBuilder})
    : uri = uri ?? Uri.parse('http://localhost');

  @override
  final Uri uri;
  @override
  final String method;
  final Future<HttpClientResponse> Function(_MockHttpClientRequest request)? responseBuilder;

  @override
  int contentLength = -1;

  final Map<String, Object> headersMap = {};
  final List<List<int>> data = [];

  @override
  HttpHeaders get headers => _MockHttpHeaders(headersMap);

  @override
  void add(List<int> chunk) => data.add(chunk);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      data.add(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    if (responseBuilder != null) {
      return responseBuilder!(this);
    }
    return _MockHttpClientResponse();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  _MockHttpHeaders([Map<String, Object>? map]) : _map = map ?? {};
  final Map<String, Object> _map;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _map[name.toLowerCase()] = value;
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _map[name.toLowerCase()] = value;
  }

  @override
  String? value(String name) => _map[name.toLowerCase()]?.toString();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  _MockHttpClientResponse({this.statusCode = HttpStatus.ok, Map<String, Object>? headersMap})
    : headersMap = headersMap ?? {'etag': '"mock-etag-1"'};

  @override
  final int statusCode;
  final Map<String, Object> headersMap;

  @override
  HttpHeaders get headers => _MockHttpHeaders(Map.from(headersMap));

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream<List<int>>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testVideoFile;
  late LocalMediaStore mediaStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    mediaStore = LocalMediaStore(prefs: prefs);

    tempDir = await Directory.systemTemp.createTemp('pt_service_test_');
    testVideoFile = File('${tempDir.path}/test_movie.mp4');
    // 25 MB file (3 parts: 10MB, 10MB, 5MB)
    final chunk = Uint8List(1024 * 1024); // 1 MB
    final sink = testVideoFile.openWrite();
    for (int i = 0; i < 25; i++) {
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MediaSharingService - Slicing & ETag Utilities', () {
    test('calculateSlices slices file properly with 10MB chunks', () {
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
      expect(slices[1].length, 10 * 1024 * 1024);

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

    test('files <= 10 MB produce exactly 1 slice', () {
      final slices = MediaSharingService.calculateSlices(
        fileSize: 8 * 1024 * 1024,
        partSizeBytes: 10 * 1024 * 1024,
      );

      expect(slices.length, 1);
      expect(slices[0].partNumber, 1);
      expect(slices[0].startOffset, 0);
      expect(slices[0].endOffset, 8 * 1024 * 1024);
    });

    test('ETag sanitization removes surrounding double quotes and trims whitespace', () {
      expect(MediaSharingService.sanitizeETag('"abcd-1234"'), 'abcd-1234');
      expect(MediaSharingService.sanitizeETag('  "xyz-987"  '), 'xyz-987');
      expect(MediaSharingService.sanitizeETag('raw-etag'), 'raw-etag');
      expect(MediaSharingService.sanitizeETag(null), '');
    });
  });

  group('MediaSharingService - Room Multipart Upload & Download', () {
    test(
      'full upload flow initiates, uploads parts with contentLength, and completes sorted',
      () async {
        final uploadedPartLengths = <int, int>{};
        final uploadedPartETags = <int, String>{};
        var completePayloadReceived = <String, dynamic>{};

        Future<Map<String, dynamic>> mockEdgeFunctionCaller(
          String action,
          Map<String, dynamic> body,
        ) async {
          if (action == 'initiate') {
            return {
              'uploadId': 'upload_abc_123',
              'r2Key': 'rooms/r1/test_movie.mp4',
              'partSizeBytes': 10 * 1024 * 1024,
              'totalParts': 3,
            };
          } else if (action == 'part-urls') {
            final partNumbers = (body['partNumbers'] as List).cast<int>();
            return {
              'parts': partNumbers
                  .map((p) => {'partNumber': p, 'url': 'https://r2.example.com/upload?part=$p'})
                  .toList(),
            };
          } else if (action == 'complete') {
            completePayloadReceived = body;
            return {'success': true, 'state': 'ready'};
          }
          throw UnimplementedError('Action $action');
        }

        final service = MediaSharingService(
          mediaStore: mediaStore,
          edgeFunctionCaller: mockEdgeFunctionCaller,
          httpClientFactory: () => _MockHttpClient((url, method) async {
            final partNum = int.parse(url.queryParameters['part']!);
            return _MockHttpClientRequest(
              uri: url,
              method: method,
              responseBuilder: (req) async {
                expect(req.contentLength, greaterThan(0));
                uploadedPartLengths[partNum] = req.contentLength;
                final etag = 'etag-part-$partNum';
                uploadedPartETags[partNum] = etag;
                return _MockHttpClientResponse(
                  statusCode: 200,
                  headersMap: {HttpHeaders.etagHeader: '"$etag"'},
                );
              },
            );
          }),
        );

        final progressEvents = <UploadProgress>[];
        final session = await service.uploadFile(
          roomId: 'r1',
          file: testVideoFile,
          onProgress: progressEvents.add,
        );

        expect(session.uploadId, 'upload_abc_123');
        expect(session.r2Key, 'rooms/r1/test_movie.mp4');
        expect(uploadedPartLengths.length, 3);
        expect(uploadedPartLengths[1], 10 * 1024 * 1024);
        expect(uploadedPartLengths[2], 10 * 1024 * 1024);
        expect(uploadedPartLengths[3], 5 * 1024 * 1024);

        final parts = (completePayloadReceived['parts'] as List).cast<Map<String, dynamic>>();
        expect(parts.length, 3);
        expect(parts[0]['partNumber'], 1);
        expect(parts[0]['etag'], 'etag-part-1');
        expect(parts[1]['partNumber'], 2);
        expect(parts[1]['etag'], 'etag-part-2');
        expect(parts[2]['partNumber'], 3);
        expect(parts[2]['etag'], 'etag-part-3');

        expect(progressEvents.isNotEmpty, isTrue);
        expect(progressEvents.last.fraction, 1.0);
      },
    );

    test('crash recovery lists parts from R2, resumes missing parts, and completes', () async {
      await mediaStore.saveUploadSession(
        roomId: 'r1',
        session: const UploadSession(
          roomId: 'r1',
          uploadId: 'crashed_upload_id',
          r2Key: 'rooms/r1/crashed.mp4',
          filePath: '/path/to/crashed.mp4',
          fileSize: 25 * 1024 * 1024,
          partSizeBytes: 10 * 1024 * 1024,
          totalParts: 3,
          completedParts: {1: 'etag-1'},
        ),
      );

      final uploadedParts = <int>[];
      var completeCalled = false;

      Future<Map<String, dynamic>> mockEdgeCaller(String action, Map<String, dynamic> body) async {
        if (action == 'list-parts') {
          return {
            'parts': [
              {'partNumber': 1, 'etag': 'etag-1', 'size': 10 * 1024 * 1024},
            ],
          };
        } else if (action == 'part-urls') {
          final partNumbers = (body['partNumbers'] as List).cast<int>();
          return {
            'parts': partNumbers
                .map((p) => {'partNumber': p, 'url': 'https://r2.example.com/upload?part=$p'})
                .toList(),
          };
        } else if (action == 'complete') {
          completeCalled = true;
          return {'success': true, 'state': 'ready'};
        }
        throw UnimplementedError('Action $action');
      }

      final service = MediaSharingService(
        mediaStore: mediaStore,
        edgeFunctionCaller: mockEdgeCaller,
        httpClientFactory: () => _MockHttpClient((url, method) async {
          final partNum = int.parse(url.queryParameters['part']!);
          uploadedParts.add(partNum);
          return _MockHttpClientRequest(
            uri: url,
            method: method,
            responseBuilder: (req) async {
              return _MockHttpClientResponse(
                statusCode: 200,
                headersMap: {HttpHeaders.etagHeader: 'etag-$partNum'},
              );
            },
          );
        }),
      );

      await service.resumeUpload(roomId: 'r1', file: testVideoFile);

      expect(uploadedParts, [2, 3]);
      expect(completeCalled, isTrue);
    });

    test('abortUpload calls edge abort and clears session from LocalMediaStore', () async {
      await mediaStore.saveUploadSession(
        roomId: 'r1',
        session: const UploadSession(
          roomId: 'r1',
          uploadId: 'upload_to_abort',
          r2Key: 'rooms/r1/abort.mp4',
          filePath: '/path/to/abort.mp4',
          fileSize: 1000,
          partSizeBytes: 1000,
          totalParts: 1,
          completedParts: {},
        ),
      );

      var edgeAbortCalled = false;
      Future<Map<String, dynamic>> mockEdgeCaller(String action, Map<String, dynamic> body) async {
        if (action == 'abort') {
          edgeAbortCalled = true;
          return {'success': true};
        }
        throw UnimplementedError('Action $action');
      }

      final service = MediaSharingService(
        mediaStore: mediaStore,
        edgeFunctionCaller: mockEdgeCaller,
      );

      await service.abortUpload(roomId: 'r1');

      expect(edgeAbortCalled, isTrue);
      expect(await mediaStore.loadUploadSession('r1'), isNull);
    });

    test('fetchDownloadUrl gets fresh stream URL and metadata', () async {
      Future<Map<String, dynamic>> mockEdgeCaller(String action, Map<String, dynamic> body) async {
        if (action == 'download-url') {
          return {
            'streamUrl': 'https://r2.example.com/download/movie.mp4?sig=xyz',
            'fileName': 'movie.mp4',
            'fileSize': 104857600,
            'expiresIn': 7200,
          };
        }
        throw UnimplementedError('Action $action');
      }

      final service = MediaSharingService(
        mediaStore: mediaStore,
        edgeFunctionCaller: mockEdgeCaller,
      );

      final dl = await service.fetchDownloadUrl(roomId: 'r1');
      expect(dl.streamUrl.toString(), 'https://r2.example.com/download/movie.mp4?sig=xyz');
      expect(dl.fileName, 'movie.mp4');
      expect(dl.fileSize, 104857600);
      expect(dl.expiresInSeconds, 7200);
    });
  });

  group('MediaSharingService - Staged User Uploads', () {
    test('uploadStagedFile orchestrates staged initiate, parts, and complete', () async {
      final calledActions = <String>[];
      final smallFile = File('${tempDir.path}/small_movie.mp4');
      await smallFile.writeAsBytes(List.filled(1024, 65));

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
        httpClientFactory: () => _MockHttpClient(),
      );

      final progressEvents = <UploadProgress>[];
      final session = await service.uploadStagedFile(
        file: smallFile,
        onProgress: progressEvents.add,
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
      final smallFile = File('${tempDir.path}/cancel_movie.mp4');
      await smallFile.writeAsBytes(List.filled(1024, 65));

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
          file: smallFile,
          cancelToken: cancelToken,
          onSessionCreated: (s) => createdSession = s,
        ),
        throwsA(isA<HttpException>()),
      );

      expect(createdSession?.stagedId, 'staged-uuid-cancel');
      expect(calledActions, contains('staged-abort'));
    });
  });
}
