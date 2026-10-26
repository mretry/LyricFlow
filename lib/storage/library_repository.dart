import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_entry.dart';

/// Stable persistence contract. Replaceable with SQLite/iCloud in future.
abstract interface class LibraryRepository {
  Future<List<MediaEntry>> load();
  Future<void> upsert(MediaEntry item);
  Future<void> remove(String id);
  Future<String> absolutePath(String relativePath);
}

class LocalLibraryRepository implements LibraryRepository {
  LocalLibraryRepository();

  static const key = 'lyricflow.library.v1';
  final _preferences = SharedPreferencesAsync();
  List<MediaEntry>? _cache;
  Future<void> _pendingWrite = Future.value();

  @override
  Future<List<MediaEntry>> load() async {
    if (_cache != null) return List.of(_cache!);
    final raw = await _preferences.getString(key);
    if (raw == null || raw.isEmpty) {
      _cache = [];
    } else {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _cache = decoded
          .map((value) => MediaEntry.fromJson(value as Map<String, dynamic>))
          .toList();
    }
    return List.of(_cache!);
  }

  @override
  Future<void> upsert(MediaEntry item) async {
    final items = await load();
    final index = items.indexWhere((entry) => entry.id == item.id);
    if (index < 0) {
      items.insert(0, item);
    } else {
      items[index] = item;
    }
    _cache = items;
    await _persist();
  }

  @override
  Future<void> remove(String id) async {
    final items = await load();
    items.removeWhere((item) => item.id == id);
    _cache = items;
    await _persist();
  }

  Future<void> _persist() {
    // Serialize writes to protect against overlapping position-save requests.
    final snapshot = jsonEncode(_cache!.map((item) => item.toJson()).toList());
    _pendingWrite = _pendingWrite.then((_) => _preferences.setString(key, snapshot));
    return _pendingWrite;
  }

  @override
  Future<String> absolutePath(String relativePath) async {
    final docs = await getApplicationDocumentsDirectory();
    final base = p.normalize(docs.path);
    final absolute = p.normalize(p.join(base, relativePath));
    if (!p.isWithin(base, absolute)) {
      throw const FileSystemException('非法媒体相对路径');
    }
    return absolute;
  }

  Future<void> deleteFiles(MediaEntry item) async {
    final fullPath = await absolutePath(item.mediaPath);
    final folder = Directory(p.dirname(fullPath));
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}
