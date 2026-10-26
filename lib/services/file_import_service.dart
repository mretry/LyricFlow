import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../models/media_entry.dart';
import '../storage/library_repository.dart';
import '../subtitles/subtitle_parser.dart';

/// A repeatable byte source. It supports both the iOS Files picker and LAN HTTP downloads.
class ImportSource {
  const ImportSource({required this.name, required this.openStream, this.size});

  final String name;
  final int? size;
  final Stream<List<int>> Function() openStream;
}

class ImportBatchResult {
  const ImportBatchResult({required this.imported, required this.errors});

  const ImportBatchResult.empty() : imported = const [], errors = const [];

  final List<MediaEntry> imported;
  final List<String> errors;
}

class FileImportService {
  FileImportService(this.repository, this.parsers);

  final LibraryRepository repository;
  final SubtitleParsers parsers;

  static const audioExtensions = {'mp3', 'm4a', 'aac', 'wav', 'flac'};
  static const videoExtensions = {'mp4', 'mov', 'm4v'};
  static const captionExtensions = {'lrc', 'srt', 'vtt', 'ass'};

  static String _ext(String file) =>
      p.extension(file).replaceFirst('.', '').toLowerCase();
  static String _base(String file) =>
      p.basenameWithoutExtension(file).trim().toLowerCase();

  Future<ImportBatchResult> pickAndImportMedia() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        ...audioExtensions,
        ...videoExtensions,
        ...captionExtensions,
      ],
    );
    if (picked.isEmpty) return const ImportBatchResult.empty();
    final sources = await Future.wait(picked.map(_fromPlatformFile));
    return importSources(sources);
  }

  /// Import files from any source while keeping the filesystem transaction safe.
  /// Failed copies are written to a .partial file and cleaned up before returning.
  Future<ImportBatchResult> importSources(List<ImportSource> sources) async {
    final errors = <String>[];
    final subtitleByBase = <String, _PreparedSubtitle>{};

    for (final source in sources) {
      final ext = _ext(source.name);
      if (!captionExtensions.contains(ext)) continue;
      try {
        final text = await _decodeSource(source);
        final cues = parsers.parse(ext, text);
        if (cues.isEmpty) {
          throw const FormatException('没有找到有效的字幕时间轴');
        }
        subtitleByBase.putIfAbsent(
          _base(source.name),
          () => _PreparedSubtitle(source: source, extension: ext),
        );
      } catch (error) {
        errors.add('字幕 ${source.name} 未配对：$error');
      }
    }

    final mediaSources = sources.where((source) {
      final ext = _ext(source.name);
      return audioExtensions.contains(ext) || videoExtensions.contains(ext);
    }).toList();
    if (mediaSources.isEmpty) {
      if (sources.isNotEmpty) errors.add('请至少选择一个音频或视频文件。');
      return ImportBatchResult(imported: const [], errors: errors);
    }

    final imported = <MediaEntry>[];
    for (var index = 0; index < mediaSources.length; index++) {
      final source = mediaSources[index];
      final ext = _ext(source.name);
      final id = '${DateTime.now().microsecondsSinceEpoch}_$index';
      final title = p.basenameWithoutExtension(source.name);
      final safeTitle = _safeFileName(title);
      final folder = p.join('media', '${safeTitle}_$id');
      final mediaPath = p.join(folder, '$safeTitle.$ext');
      var repositoryWriteAttempted = false;
      try {
        await _copySource(source, mediaPath);
        var entry = MediaEntry(
          id: id,
          title: title,
          kind: videoExtensions.contains(ext)
              ? MediaKind.video
              : MediaKind.audio,
          mediaPath: mediaPath,
          createdAt: DateTime.now(),
        );

        final subtitle = subtitleByBase[_base(source.name)];
        if (subtitle != null) {
          final subtitlePath = p.join(folder, 'captions.${subtitle.extension}');
          await _copySource(subtitle.source, subtitlePath);
          entry = entry.copyWith(subtitlePath: subtitlePath);
        }

        repositoryWriteAttempted = true;
        await repository.upsert(entry);
        imported.add(entry);
      } catch (error) {
        if (repositoryWriteAttempted) {
          try {
            await repository.remove(id);
          } catch (_) {
            // Keep the original import error; filesystem cleanup still runs below.
          }
        }
        try {
          await repository.deleteFilesByPath(mediaPath);
        } catch (_) {
          // Best effort cleanup; the .partial writer also cleans its own temporary file.
        }
        errors.add('文件 ${source.name} 导入失败：$error');
      }
    }

    return ImportBatchResult(imported: imported, errors: errors);
  }

  Future<MediaEntry?> pickAndAttachSubtitle(MediaEntry item) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: captionExtensions.toList(),
    );
    if (picked == null) return null;

    final source = await _fromPlatformFile(picked);
    final ext = _ext(picked.name);
    final text = await _decodeSource(source);
    final cues = parsers.parse(ext, text);
    if (cues.isEmpty) {
      throw const FormatException('字幕文件中没有有效的时间轴和文字');
    }

    final folder = p.dirname(item.mediaPath);
    final relative = p.join(
      folder,
      'captions_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    await _copySource(source, relative);
    try {
      final updated = item.copyWith(subtitlePath: relative);
      await repository.upsert(updated);
      final oldPath = item.subtitlePath;
      if (oldPath != null && oldPath != relative) {
        try {
          final oldAbsolute = await repository.absolutePath(oldPath);
          final oldFile = File(oldAbsolute);
          if (await oldFile.exists()) await oldFile.delete();
        } catch (_) {
          // A stale old subtitle must not undo a successful replacement.
        }
      }
      return updated;
    } catch (_) {
      try {
        final absolute = await repository.absolutePath(relative);
        final file = File(absolute);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<String> readSubtitle(MediaEntry item) async {
    final subtitle = item.subtitlePath;
    if (subtitle == null) return '';
    final absolute = await repository.absolutePath(subtitle);
    return utf8
        .decode(await File(absolute).readAsBytes())
        .replaceFirst('\uFEFF', '');
  }

  Future<ImportSource> _fromPlatformFile(PlatformFile file) async =>
      ImportSource(
        name: file.name,
        size: file.lengthSync() ?? await file.length(),
        openStream: file.readAsByteStream,
      );

  Future<String> _decodeSource(ImportSource source) async {
    final bytes = await source.openStream().fold<List<int>>(<int>[], (
      buffer,
      chunk,
    ) {
      buffer.addAll(chunk);
      return buffer;
    });
    return utf8.decode(bytes).replaceFirst('\uFEFF', '');
  }

  Future<void> _copySource(ImportSource source, String relative) async {
    final absolute = await repository.absolutePath(relative);
    final target = File(absolute);
    final partial = File('$absolute.partial');
    await target.parent.create(recursive: true);

    IOSink? output;
    var written = 0;
    try {
      if (await partial.exists()) await partial.delete();
      final sink = partial.openWrite(mode: FileMode.writeOnly);
      output = sink;
      await sink.addStream(
        source.openStream().map((chunk) {
          written += chunk.length;
          return chunk;
        }),
      );
      await sink.flush();
      await sink.close();
      output = null;

      if (source.size != null && written != source.size) {
        throw FileSystemException(
          '文件长度不完整（预期 ${source.size} 字节，实际 $written 字节）',
          source.name,
        );
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
    } catch (_) {
      if (output != null) {
        try {
          await output.close();
        } catch (_) {}
      }
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      rethrow;
    }
  }

  String _safeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\u0000-\u001F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    return cleaned.isEmpty ? 'Untitled' : cleaned;
  }
}

class _PreparedSubtitle {
  const _PreparedSubtitle({required this.source, required this.extension});
  final ImportSource source;
  final String extension;
}
