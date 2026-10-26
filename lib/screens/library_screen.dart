import 'package:flutter/material.dart';

import '../models/media_entry.dart';
import '../services/file_import_service.dart';
import '../storage/library_repository.dart';
import '../subtitles/subtitle_parser.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _repository = LocalLibraryRepository();
  late final FileImportService _importer =
      FileImportService(_repository, SubtitleParsers());
  List<MediaEntry> _items = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final items = await _repository.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '媒体库读取失败：$e');
    }
  }

  Future<void> _importFiles() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final created = await _importer.pickAndImportMedia();
      await _refresh();
      if (created.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${created.length} 个媒体文件')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择音频或视频；字幕也可与媒体一起选中')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(MediaEntry item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          initialItem: item,
          repository: _repository,
          importer: _importer,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _remove(MediaEntry item) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地媒体？'),
        content: Text('将删除「${item.title}」及它导入到 App 中的字幕副本。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (answer != true) return;
    try {
      await _repository.remove(item.id);
      await _repository.deleteFiles(item);
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LyricFlow', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .4)),
        actions: [
          IconButton(
            tooltip: '导入文件',
            onPressed: _busy ? null : _importFiles,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  const Text('你的媒体库', style: TextStyle(fontSize: 31, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text('让每一句歌词与字幕，都能成为播放入口。',
                    style: TextStyle(color: Color(0xFF9E9AAF))),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _busy ? null : _importFiles,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_upload_outlined),
                    label: Text(_busy ? '正在导入…' : '导入音频、视频与字幕'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: const Color(0xFFC9ABFF),
                      foregroundColor: const Color(0xFF1B1527),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('支持 MP3 / M4A / WAV / MP4 / MOV 与 LRC / SRT / VTT\n可同时选择同名的媒体与字幕文件自动配对',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.55, color: Color(0xFF868497))),
                  const SizedBox(height: 26),
                  if (_error != null)
                    Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
                  Expanded(
                    child: _items.isEmpty
                        ? const _EmptyLibrary()
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              return Material(
                                color: const Color(0xFF1A1C29),
                                borderRadius: BorderRadius.circular(18),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  leading: Container(
                                    height: 48, width: 48,
                                    decoration: BoxDecoration(
                                      color: item.kind == MediaKind.video
                                          ? const Color(0xFF28423F) : const Color(0xFF3F2D55),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      item.kind == MediaKind.video ? Icons.movie_outlined : Icons.music_note_rounded,
                                      color: const Color(0xFFDDD2FF),
                                    ),
                                  ),
                                  title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    '${item.kind == MediaKind.video ? '视频' : '音频'}  ·  ${item.subtitlePath != null ? '已配对字幕' : '尚未配对字幕'}',
                                    style: const TextStyle(color: Color(0xFF9997A9)),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (action) {
                                      if (action == 'delete') _remove(item);
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'delete', child: Text('删除')),
                                    ],
                                  ),
                                  onTap: () => _open(item),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.queue_music_rounded, size: 80, color: Color(0xFF5C5871)),
        SizedBox(height: 18),
        Text('媒体库还是空的', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        Text('从上方导入第一段音频或视频', style: TextStyle(color: Color(0xFF8D8B9D))),
      ],
    ),
  );
}
