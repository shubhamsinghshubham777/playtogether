import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/media_sharing_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('MediaSharingException', () {
    test('parses quota_exceeded FunctionException with structured details', () {
      final exc = FunctionException(
        status: 400,
        details: {
          'error': 'quota_exceeded',
          'details': {
            'error': 'quota_exceeded',
            'allowed': false,
            'used_bytes': 2440779498,
            'weekly_limit': 4294967296,
            'resets_at': '2026-09-05T19:12:24.052023+00:00',
          },
        },
        reasonPhrase: 'Bad Request',
      );

      final parsed = MediaSharingException.fromError(exc);
      expect(parsed.code, 'quota_exceeded');
      expect(parsed.message, contains('Weekly upload quota reached'));
      expect(parsed.message, contains('2.3 GB of 4.0 GB used'));
      expect(parsed.usedBytes, 2440779498);
      expect(parsed.weeklyLimitBytes, 4294967296);
      expect(parsed.resetsAt, isNotNull);
    });

    test('parses concurrent_upload_active error', () {
      final parsed = MediaSharingException.fromError({'error': 'concurrent_upload_active'});
      expect(parsed.code, 'concurrent_upload_active');
      expect(parsed.message, contains('Another upload is already in progress'));
    });

    test('parses file_too_large error', () {
      final parsed = MediaSharingException.fromError({'error': 'file_too_large'});
      expect(parsed.code, 'file_too_large');
      expect(parsed.message, contains('maximum file size limit'));
    });

    test('parses cancellation', () {
      final parsed = MediaSharingException.fromError('Upload cancelled');
      expect(parsed.code, 'cancelled');
      expect(parsed.message, 'Upload was cancelled.');
    });
  });
}
