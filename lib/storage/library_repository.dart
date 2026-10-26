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
  Future<void> deleteFilesByPath(String relativePath);
}

class LocalLibraryRepository implements LibraryRepository {
  LocalLibraryRepository();

  static const key = 'lyricflow.library.v1';
  final _preferences = SharedPreferencesAsync();
  List<MediaEntry>? _cache;
  Future<void> _pendingWrite = Future.value();
  bool _cleanupDone = false;

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
    if (!_cleanupDone) {
      _cleanupDone = true;
      try {
        await _cleanupFailedImportArtifacts();
      } catch (_) {
        // Startup cleanup is best-effort and must not prevent opening the library.
      }
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
    _pendingWrite = _pendingWrite
        .catchError((Object _) {})
        .then((_) => _preferences.setString(key, snapshot));
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

  Future<void> _cleanupFailedImportArtifacts() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'media'));
    if (!await root.exists()) return;

    final knownDirectories = _cache!
        .map((item) => p.normalize(p.dirname(item.mediaPath)))
        .toSet();
    final generatedDirectory = RegExp(r'^(?:.+_)?\d{15,}_\d+$');

    // A prior interrupted import can leave a large completed copy without a
    // library record. Only remove directories matching our generated naming
    // convention; arbitrary user-created folders remain untouched.
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final relative = p.normalize(p.relative(entity.path, from: docs.path));
      await for (final file in entity.list(
        recursive: true,
        followLinks: false,
      )) {
        if (file is File && file.path.endsWith('.partial')) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      if (knownDirectories.contains(relative)) continue;
      final directoryName = p.basename(entity.path);
      if (!generatedDirectory.hasMatch(directoryName)) continue;
      final files = await entity
          .list(recursive: true, followLinks: false)
          .where((entry) => entry is File)
          .cast<File>()
          .toList();
      final titleMatch = RegExp(
        r'^(.*)_\d{15,}_\d+$',
      ).firstMatch(directoryName);
      final titlePrefix = titleMatch?.group(1);
      final containsImportArtifact = files.any((file) {
        final name = p.basename(file.path);
        return name.endsWith('.partial') ||
            RegExp(
              r'^original\.(mp3|m4a|aac|wav|flac|mp4|mov|m4v)$',
            ).hasMatch(name) ||
            name.startsWith('captions.') ||
            (titlePrefix != null && name.startsWith('$titlePrefix.'));
      });
      if (files.isEmpty || containsImportArtifact) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> deleteFiles(MediaEntry item) =>
      deleteFilesByPath(item.mediaPath);

  @override
  Future<void> deleteFilesByPath(String relativePath) async {
    final fullPath = await absolutePath(relativePath);
    final folder = Directory(p.dirname(fullPath));
    if (await folder.exists()) await folder.delete(recursive: true);
  }
}
