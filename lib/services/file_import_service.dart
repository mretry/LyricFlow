import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../models/media_entry.dart';
import '../subtitles/subtitle_parser.dart';
import '../storage/library_repository.dart';

class FileImportService {
  FileImportService(this.repository, this.parsers);

  final LibraryRepository repository;
  final SubtitleParsers parsers;

  static const audioExtensions = {'mp3', 'm4a', 'aac', 'wav', 'flac'};
  static const videoExtensions = {'mp4', 'mov', 'm4v'};
  static const captionExtensions = {'lrc', 'srt', 'vtt'};

  static String _ext(String file) =>
      p.extension(file).replaceFirst('.', '').toLowerCase();
  static String _base(String file) =>
      p.basenameWithoutExtension(file).trim().toLowerCase();

  /// A single picker can select media + subtitles; same-basename files pair.
  Future<List<MediaEntry>> pickAndImportMedia() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        ...audioExtensions,
        ...videoExtensions,
        ...captionExtensions,
      ],
    );
    if (picked.isEmpty) return [];
    final subtitleFiles = <String, PlatformFile>{};
    for (final file in picked) {
      if (captionExtensions.contains(_ext(file.name))) {
        subtitleFiles.putIfAbsent(_base(file.name), () => file);
      }
    }
    final created = <MediaEntry>[];
    for (final file in picked) {
      final ext = _ext(file.name);
      if (!audioExtensions.contains(ext) && !videoExtensions.contains(ext)) {
        continue;
      }
      final id = '${DateTime.now().microsecondsSinceEpoch}_${created.length}';
      final mediaPath = p.join('media', id, 'original.$ext');
      await _copyFile(file, mediaPath);
      MediaEntry entry = MediaEntry(
        id: id,
        title: p.basenameWithoutExtension(file.name),
        kind: videoExtensions.contains(ext) ? MediaKind.video : MediaKind.audio,
        mediaPath: mediaPath,
        createdAt: DateTime.now(),
      );
      final subtitle = subtitleFiles[_base(file.name)];
      if (subtitle != null) {
        try {
          final text = await _decodeSubtitle(subtitle);
          final parsed = parsers.parse(_ext(subtitle.name), text);
          if (parsed.isNotEmpty) {
            final subPath = p.join(
              'media',
              id,
              'captions.${_ext(subtitle.name)}',
            );
            await _copyFile(subtitle, subPath);
            entry = entry.copyWith(subtitlePath: subPath);
          }
        } on FormatException {
          // Keep imported media even when an automatically matched subtitle is invalid.
        }
      }
      await repository.upsert(entry);
      created.add(entry);
    }
    return created;
  }

  Future<MediaEntry?> pickAndAttachSubtitle(MediaEntry item) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: captionExtensions.toList(),
    );
    if (picked == null) return null;
    final ext = _ext(picked.name);
    final text = await _decodeSubtitle(picked);
    final cues = parsers.parse(ext, text);
    if (cues.isEmpty) throw const FormatException('字幕文件中没有有效的时间轴和文字');
    final relative = p.join('media', item.id, 'captions.$ext');
    await _copyFile(picked, relative);
    final updated = item.copyWith(subtitlePath: relative);
    await repository.upsert(updated);
    return updated;
  }

  Future<String> readSubtitle(MediaEntry item) async {
    final subtitle = item.subtitlePath;
    if (subtitle == null) return '';
    final absolute = await repository.absolutePath(subtitle);
    // UTF-8 with BOM supported. Other encodings will be reported to the user.
    return utf8
        .decode(await File(absolute).readAsBytes())
        .replaceFirst('\uFEFF', '');
  }

  Future<String> _decodeSubtitle(PlatformFile file) async {
    final contents = await file.readAsBytes();
    return utf8.decode(contents).replaceFirst('\uFEFF', '');
  }

  Future<void> _copyFile(PlatformFile picked, String relative) async {
    final absolute = await repository.absolutePath(relative);
    final target = File(absolute);
    await target.parent.create(recursive: true);
    // Stream rather than loading an entire movie into RAM.
    final output = target.openWrite();
    try {
      await output.addStream(picked.readAsByteStream());
    } finally {
      await output.close();
    }
  }
}
