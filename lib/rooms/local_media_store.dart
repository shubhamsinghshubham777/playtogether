import 'dart:convert';
import 'dart:io';

import 'package:playtogether/diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kStoreKey = 'pt.local_media_by_room';
const _kUploadSessionKey = 'pt.upload_sessions_by_room';
const kLocalMediaTtl = Duration(days: 35);
const _kMaxEntries = 64;

class UploadSession {
  const UploadSession({
    required this.roomId,
    required this.uploadId,
    required this.r2Key,
    required this.filePath,
    required this.fileSize,
    required this.partSizeBytes,
    required this.totalParts,
    this.completedParts = const {},
  });

  final String roomId;
  final String uploadId;
  final String r2Key;
  final String filePath;
  final int fileSize;
  final int partSizeBytes;
  final int totalParts;
  final Map<int, String> completedParts; // partNumber -> etag

  UploadSession copyWith({
    Map<int, String>? completedParts,
  }) {
    return UploadSession(
      roomId: roomId,
      uploadId: uploadId,
      r2Key: r2Key,
      filePath: filePath,
      fileSize: fileSize,
      partSizeBytes: partSizeBytes,
      totalParts: totalParts,
      completedParts: completedParts ?? this.completedParts,
    );
  }

  factory UploadSession.fromJson(Map<String, dynamic> json) => UploadSession(
    roomId: json['room_id'] as String,
    uploadId: json['upload_id'] as String,
    r2Key: json['r2_key'] as String,
    filePath: json['file_path'] as String,
    fileSize: (json['file_size'] as num).toInt(),
    partSizeBytes: (json['part_size_bytes'] as num).toInt(),
    totalParts: (json['total_parts'] as num).toInt(),
    completedParts: (json['completed_parts'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(int.parse(k), v as String),
    ) ?? const {},
  );

  Map<String, Object?> toJson() => {
    'room_id': roomId,
    'upload_id': uploadId,
    'r2_key': r2Key,
    'file_path': filePath,
    'file_size': fileSize,
    'part_size_bytes': partSizeBytes,
    'total_parts': totalParts,
    'completed_parts': completedParts.map((k, v) => MapEntry(k.toString(), v)),
  };
}

class LocalMediaEntry {
  const LocalMediaEntry({required this.name, required this.path, required this.touchedAt});

  final String name;
  final String path;
  final DateTime touchedAt;

  factory LocalMediaEntry.fromJson(Map<String, dynamic> json) => LocalMediaEntry(
    name: json['name'] as String,
    path: json['path'] as String,
    touchedAt: DateTime.fromMillisecondsSinceEpoch((json['touched_at'] as num?)?.toInt() ?? 0),
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'touched_at': touchedAt.millisecondsSinceEpoch,
  };

  bool get fileStillExists {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}

class LocalMediaStore {
  // ignore: prefer_initializing_formals
  LocalMediaStore({SharedPreferences? prefs}) : _prefs = prefs;
  LocalMediaStore._() : _prefs = null;
  static final instance = LocalMediaStore._();

  final SharedPreferences? _prefs;
  Future<SharedPreferences> get _asyncPrefs async => _prefs ?? await SharedPreferences.getInstance();

  Map<String, LocalMediaEntry>? _cache;
  Map<String, UploadSession>? _uploadSessionCache;

  Future<Map<String, LocalMediaEntry>> _read() async {
    final cached = _cache;
    if (cached != null) return cached;
    final entries = <String, LocalMediaEntry>{};
    try {
      final raw = (await _asyncPrefs).getString(_kStoreKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          entries[entry.key] = LocalMediaEntry.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          );
        }
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading the local media map');
    }
    _cache = entries;
    return entries;
  }

  Future<void> _write(Map<String, LocalMediaEntry> entries) async {
    _cache = entries;
    try {
      final encoded = jsonEncode({
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      });
      await (await _asyncPrefs).setString(_kStoreKey, encoded);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'writing the local media map');
    }
  }

  Future<Map<String, UploadSession>> _readSessions() async {
    final cached = _uploadSessionCache;
    if (cached != null) return cached;
    final entries = <String, UploadSession>{};
    try {
      final raw = (await _asyncPrefs).getString(_kUploadSessionKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          entries[entry.key] = UploadSession.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          );
        }
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'reading upload sessions');
    }
    _uploadSessionCache = entries;
    return entries;
  }

  Future<void> _writeSessions(Map<String, UploadSession> entries) async {
    _uploadSessionCache = entries;
    try {
      final encoded = jsonEncode({
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      });
      await (await _asyncPrefs).setString(_kUploadSessionKey, encoded);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'writing upload sessions');
    }
  }

  Future<UploadSession?> loadUploadSession(String roomId) async => (await _readSessions())[roomId];

  Future<void> saveUploadSession({
    required String roomId,
    required UploadSession session,
  }) async {
    final entries = Map<String, UploadSession>.from(await _readSessions());
    entries[roomId] = session;
    await _writeSessions(entries);
  }

  Future<void> clearUploadSession(String roomId) async {
    final entries = Map<String, UploadSession>.from(await _readSessions());
    if (entries.remove(roomId) == null) return;
    await _writeSessions(entries);
  }

  Future<LocalMediaEntry?> lookup(String roomId) async => (await _read())[roomId];

  Future<void> record({
    required String roomId,
    required String name,
    required String? path,
    DateTime? now,
  }) async {
    if (path == null || path.isEmpty) return;
    final entries = Map<String, LocalMediaEntry>.from(await _read());
    entries[roomId] = LocalMediaEntry(name: name, path: path, touchedAt: now ?? DateTime.now());
    await _write(_capped(entries));
  }

  Future<void> forget(String roomId) async {
    final entries = Map<String, LocalMediaEntry>.from(await _read());
    if (entries.remove(roomId) == null) return;
    await _write(entries);
  }

  Future<void> prune({required Set<String> keepRoomIds, DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final entries = await _read();
    final kept = <String, LocalMediaEntry>{
      for (final entry in entries.entries)
        if (keepRoomIds.contains(entry.key) &&
            clock.difference(entry.value.touchedAt) <= kLocalMediaTtl)
          entry.key: entry.value,
    };
    if (kept.length == entries.length) return;
    await _write(kept);
  }

  Map<String, LocalMediaEntry> _capped(Map<String, LocalMediaEntry> entries) {
    if (entries.length <= _kMaxEntries) return entries;
    final ordered = entries.entries.toList()
      ..sort((a, b) => b.value.touchedAt.compareTo(a.value.touchedAt));
    return {for (final entry in ordered.take(_kMaxEntries)) entry.key: entry.value};
  }
}
