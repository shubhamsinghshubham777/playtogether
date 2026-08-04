import 'dart:convert';
import 'dart:io';

import 'package:playtogether/diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kStoreKey = 'pt.local_media_by_room';
const kLocalMediaTtl = Duration(days: 35);
const _kMaxEntries = 64;

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
  LocalMediaStore._();
  static final instance = LocalMediaStore._();

  Map<String, LocalMediaEntry>? _cache;

  Future<Map<String, LocalMediaEntry>> _read() async {
    final cached = _cache;
    if (cached != null) return cached;
    final entries = <String, LocalMediaEntry>{};
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kStoreKey);
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
      await (await SharedPreferences.getInstance()).setString(_kStoreKey, encoded);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'writing the local media map');
    }
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
