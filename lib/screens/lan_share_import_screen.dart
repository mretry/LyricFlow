import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/file_import_service.dart';
import '../services/lan_share_client.dart';

class LanShareImportScreen extends StatefulWidget {
  const LanShareImportScreen({required this.importer, super.key});

  final FileImportService importer;

  @override
  State<LanShareImportScreen> createState() => _LanShareImportScreenState();
}

class _LanShareImportScreenState extends State<LanShareImportScreen> {
  LanShareClient? _client;
  List<LanShareFile> _files = [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _importing = false;
  String? _error;

  Future<void> _connectFromQr(String rawValue) async {
    if (_loading || _client != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    LanShareClient? client;
    try {
      client = LanShareClient.fromQrText(rawValue);
      final files = await client.listFiles();
      if (!mounted) {
        client.close();
        return;
      }
      setState(() {
        _client = client;
        _files = files;
        _selected
          ..clear()
          ..addAll(files.map((file) => file.path));
        _loading = false;
      });
    } catch (error) {
      client?.close();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '连接电脑失败：$error';
        });
      }
    }
  }

  Future<void> _importSelected() async {
    final client = _client;
    if (client == null || _importing) return;
    final chosen = _files
        .where((file) => _selected.contains(file.path))
        .toList();
    if (chosen.isEmpty) {
      setState(() => _error = '请先选择要导入的文件。');
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await widget.importer.importSources(
        chosen.map((file) => file.asImportSource(client)).toList(),
      );
      if (!mounted) return;
      final message = StringBuffer('成功导入 ${result.imported.length} 个媒体文件');
      if (result.errors.isNotEmpty) {
        message.write('；${result.errors.length} 项提示/失败');
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message.toString())));
      if (result.errors.isNotEmpty) {
        setState(() => _error = result.errors.take(4).join('\n'));
      }
      if (result.imported.isNotEmpty) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _resetScanner() {
    _client?.close();
    setState(() {
      _client = null;
      _files = [];
      _selected.clear();
      _error = null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final connected = _client != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(connected ? '选择电脑文件' : '从电脑接收文件'),
        actions: [
          if (connected)
            IconButton(
              tooltip: '重新扫描二维码',
              onPressed: _loading || _importing ? null : _resetScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
        ],
      ),
      body: SafeArea(child: connected ? _filePickerBody() : _scannerBody()),
      bottomNavigationBar: connected
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                onPressed: _importing || _selected.isEmpty
                    ? null
                    : _importSelected,
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  _importing ? '正在下载并导入…' : '导入所选文件（${_selected.length}）',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            )
          : null,
    );
  }

  Widget _scannerBody() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        '在 Windows 电脑上启动 LyricFlow 局域网共享工具，然后扫描电脑浏览器中显示的二维码。',
        style: TextStyle(fontSize: 15, height: 1.5),
      ),
      const SizedBox(height: 18),
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!_loading)
                MobileScanner(
                  onDetect: (capture) {
                    if (capture.barcodes.isEmpty) return;
                    final value = capture.barcodes.first.rawValue;
                    if (value != null) unawaited(_connectFromQr(value));
                  },
                )
              else
                const ColoredBox(
                  color: Color(0xFF171923),
                  child: Center(child: CircularProgressIndicator()),
                ),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFC9ABFF),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('正在连接电脑…')),
        ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      ],
      const SizedBox(height: 16),
      const Text(
        '确保 iPhone/iPad 与电脑连接同一个 Wi-Fi。Windows 防火墙弹出提示时，允许 Python 在专用网络中通信。',
        style: TextStyle(color: Color(0xFF9E9AAF), height: 1.5, fontSize: 12),
      ),
    ],
  );

  Widget _filePickerBody() {
    final allSelected = _files.isNotEmpty && _selected.length == _files.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '找到 ${_files.length} 个文件',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (allSelected) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(_files.map((file) => file.path));
                  }
                }),
                child: Text(allSelected ? '取消全选' : '全选'),
              ),
            ],
          ),
        ),
        if (_files.isEmpty)
          const Expanded(child: Center(child: Text('共享目录中没有支持的音视频或字幕文件。')))
        else
          Expanded(
            child: ListView.separated(
              itemCount: _files.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final file = _files[index];
                final caption = FileImportService.captionExtensions.contains(
                  file.extension,
                );
                return CheckboxListTile(
                  value: _selected.contains(file.path),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(file.path);
                    } else {
                      _selected.remove(file.path);
                    }
                  }),
                  secondary: Icon(
                    caption ? Icons.subtitles_outlined : Icons.movie_outlined,
                  ),
                  title: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${caption ? '字幕' : '媒体'} · ${_sizeLabel(file.size)}',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
