import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../models/media_entry.dart';
import '../models/timed_cue.dart';
import '../playback/media_playback.dart';
import '../playback/playback_factory.dart';
import '../services/file_import_service.dart';
import '../storage/library_repository.dart';
import '../storage/app_settings_repository.dart';
import '../subtitles/cue_sync.dart';
import '../subtitles/subtitle_parser.dart';
import '../widgets/cue_list.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.initialItem,
    required this.repository,
    required this.importer,
    super.key,
  });

  final MediaEntry initialItem;
  final LibraryRepository repository;
  final FileImportService importer;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  final _sync = const CueSync();
  final _settings = AppSettingsRepository();
  final _cueListKey = GlobalKey<CueListState>();
  late MediaEntry _item = widget.initialItem;
  MediaPlayback? _player;
  List<TimedCue> _cues = [];
  int _activeIndex = -1;
  bool _follow = true;
  bool _loading = true;
  bool _subtitleBusy = false;
  double _fontSize = 22.0;
  double? _scrubMs;
  String? _error;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFontSize();
    _initialize();
  }

  Future<void> _loadFontSize() async {
    try {
      final value = await _settings.loadSubtitleFontSize();
      if (mounted) setState(() => _fontSize = value);
    } catch (_) {
      // A missing preferences store should not block media playback.
    }
  }

  Future<void> _initialize() async {
    final player = DefaultPlaybackFactory().create(_item.kind);
    _player = player;
    player.addListener(_onPlayerChange);
    try {
      final path = await widget.repository.absolutePath(_item.mediaPath);
      await player.open(path);
      if (_item.lastPositionMs > 0 &&
          _item.lastPositionMs < player.duration.inMilliseconds) {
        await player.seek(Duration(milliseconds: _item.lastPositionMs));
      }
      await _readCues();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '媒体无法打开：$e';
        });
      }
    }
  }

  Future<void> _readCues() async {
    final subtitlePath = _item.subtitlePath;
    if (subtitlePath == null) {
      if (mounted) {
        setState(() {
          _cues = [];
          _activeIndex = -1;
        });
      }
      return;
    }
    try {
      final text = await widget.importer.readSubtitle(_item);
      final extension = p.extension(subtitlePath).replaceFirst('.', '');
      final cues = SubtitleParsers().parse(extension, text);
      if (!mounted) return;
      setState(() {
        _cues = cues;
        _activeIndex = _sync.activeIndex(
          cues,
          _player?.position ?? Duration.zero,
          offsetMs: _item.subtitleOffsetMs,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = '字幕读取失败（需 UTF-8 编码）：$e');
    }
  }

  void _onPlayerChange() {
    if (!mounted) return;
    final player = _player;
    if (player == null) return;
    final next = _sync.activeIndex(
      _cues,
      player.position,
      offsetMs: _item.subtitleOffsetMs,
    );
    if (next != _activeIndex) setState(() => _activeIndex = next);
    final now = DateTime.now();
    if (now.difference(_lastSave).inSeconds >= 5 && player.initialized) {
      _lastSave = now;
      _saveProgress();
    }
  }

  Future<void> _saveProgress() async {
    final player = _player;
    if (player == null || !player.initialized) return;
    final newPosition = player.position.inMilliseconds;
    _item = _item.copyWith(lastPositionMs: newPosition);
    try {
      await widget.repository.upsert(_item);
    } catch (_) {
      // An intermittent storage failure must never interrupt playback.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_saveProgress());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player?.removeListener(_onPlayerChange);
    unawaited(_saveProgress());
    _player?.dispose();
    super.dispose();
  }

  Future<void> _chooseSubtitle() async {
    if (_subtitleBusy) return;
    setState(() => _subtitleBusy = true);
    try {
      final updated = await widget.importer.pickAndAttachSubtitle(_item);
      if (updated != null) {
        _item = updated;
        await _readCues();
        if (mounted) {
          setState(() {
            _follow = true;
            _error = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('字幕导入失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _subtitleBusy = false);
    }
  }

  Future<void> _seekCue(TimedCue cue) async {
    final player = _player;
    if (player == null || !player.initialized) return;
    setState(() => _follow = true);
    await player.seek(_sync.jumpTime(cue, offsetMs: _item.subtitleOffsetMs));
    if (!player.playing) await player.play();
  }

  Future<void> _updateOffset(int offsetMs) async {
    _item = _item.copyWith(subtitleOffsetMs: offsetMs);
    if (mounted) {
      setState(() {
        _activeIndex = _sync.activeIndex(
          _cues,
          _player?.position ?? Duration.zero,
          offsetMs: offsetMs,
        );
      });
    }
    try {
      await widget.repository.upsert(_item);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('字幕偏移保存失败：$error')));
      }
    }
  }

  Future<void> _saveFontSize(double value) async {
    try {
      await _settings.saveSubtitleFontSize(value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('字体设置保存失败：$error')));
      }
    }
  }

  void _offsetSettings() {
    var draftMs = _item.subtitleOffsetMs.toDouble();
    final secondsController = TextEditingController(
      text: (draftMs / 1000).toStringAsFixed(3),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          void setDraft(double value, {bool save = false}) {
            draftMs = value.clamp(-600000.0, 600000.0).toDouble();
            setLocalState(() {});
            if (save) {
              secondsController.text = (draftMs / 1000).toStringAsFixed(3);
              unawaited(_updateOffset(draftMs.round()));
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                10,
                24,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '手动校准字幕时间轴',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '正值：字幕整体延后；负值：字幕整体提前。设置会保存到当前媒体。',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9691A4)),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '${draftMs >= 0 ? '+' : ''}${(draftMs / 1000).toStringAsFixed(3)} 秒',
                      style: const TextStyle(
                        fontSize: 26,
                        color: Color(0xFFC9ABFF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Slider(
                    value: draftMs.clamp(-30000.0, 30000.0).toDouble(),
                    min: -30000,
                    max: 30000,
                    divisions: 600,
                    onChanged: (changed) => setDraft(changed),
                    onChangeEnd: (changed) => setDraft(changed, save: true),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: secondsController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: '手动输入偏移（秒）',
                            helperText: '可输入正数或负数，最多 ±600 秒',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (text) {
                            final seconds = double.tryParse(text.trim());
                            if (seconds == null) return;
                            setDraft(seconds * 1000, save: true);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () {
                          final seconds = double.tryParse(
                            secondsController.text.trim(),
                          );
                          if (seconds != null) {
                            setDraft(seconds * 1000, save: true);
                          }
                          FocusScope.of(context).unfocus();
                        },
                        child: const Text('应用'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final step in const [
                        -1000,
                        -100,
                        -10,
                        10,
                        100,
                        1000,
                      ])
                        OutlinedButton(
                          onPressed: () => setDraft(draftMs + step, save: true),
                          child: Text('${step > 0 ? '+' : ''}$step ms'),
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: () => setDraft(0, save: true),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('恢复 0 秒'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(secondsController.dispose);
  }

  void _fontSettings() {
    var draftSize = _fontSize;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '字幕字体大小',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  '预览：长字幕会自动换行，不再限制为固定三行。',
                  style: TextStyle(
                    fontSize: draftSize,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.text_decrease_rounded),
                    Expanded(
                      child: Slider(
                        value: draftSize,
                        min: 14,
                        max: 36,
                        divisions: 22,
                        label: '${draftSize.round()} pt',
                        onChanged: (value) =>
                            setLocalState(() => draftSize = value),
                        onChangeEnd: (value) {
                          setState(() => _fontSize = value);
                          unawaited(_saveFontSize(value));
                        },
                      ),
                    ),
                    const Icon(Icons.text_increase_rounded),
                  ],
                ),
                Center(
                  child: Text(
                    '${draftSize.round()} pt',
                    style: const TextStyle(color: Color(0xFFC9ABFF)),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    setState(() => _fontSize = draftSize);
                    unawaited(_saveFontSize(draftSize));
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('保存字体大小'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _format(Duration duration) {
    final total = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _video() {
    final controller = _player?.videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final ratio = controller.value.aspectRatio;
    return AspectRatio(
      aspectRatio: ratio > 0 ? ratio : 16 / 9,
      child: ColoredBox(color: Colors.black, child: VideoPlayer(controller)),
    );
  }

  Widget _lyricsArea() {
    return Stack(
      children: [
        CueList(
          key: _cueListKey,
          cues: _cues,
          activeIndex: _activeIndex,
          follow: _follow,
          onManualScroll: () => setState(() => _follow = false),
          onTapCue: (cue) => unawaited(_seekCue(cue)),
          fontSize: _fontSize,
        ),
        if (!_follow && _cues.isNotEmpty)
          Positioned(
            top: 10,
            right: 20,
            child: FilledButton.tonalIcon(
              onPressed: () {
                setState(() => _follow = true);
                _cueListKey.currentState?.jumpToActive();
              },
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('跟随播放'),
            ),
          ),
      ],
    );
  }

  Widget _controls() {
    final player = _player;
    if (player == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final maxMs = player.duration.inMilliseconds.toDouble();
        final currentMs = player.position.inMilliseconds.toDouble();
        final sliderMax = maxMs > 0 ? maxMs : 1.0;
        final value = (_scrubMs ?? currentMs).clamp(0.0, sliderMax).toDouble();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                ),
                child: Slider(
                  value: value,
                  min: 0,
                  max: sliderMax,
                  onChanged: maxMs == 0
                      ? null
                      : (newMs) => setState(() => _scrubMs = newMs),
                  onChangeEnd: (newMs) {
                    setState(() => _scrubMs = null);
                    unawaited(
                      player.seek(Duration(milliseconds: newMs.round())),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _format(Duration(milliseconds: value.round())),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9F9AAC),
                    ),
                  ),
                  Text(
                    _format(player.duration),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9F9AAC),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DropdownButton<double>(
                    value: player.speed,
                    underline: const SizedBox.shrink(),
                    dropdownColor: const Color(0xFF262535),
                    items: const [.5, .75, 1.0, 1.25, 1.5, 2.0]
                        .map(
                          (s) =>
                              DropdownMenuItem(value: s, child: Text('${s}x')),
                        )
                        .toList(),
                    onChanged: (s) {
                      if (s != null) unawaited(player.setSpeed(s));
                    },
                  ),
                  IconButton(
                    tooltip: '后退 10 秒',
                    iconSize: 32,
                    onPressed: () => unawaited(
                      player.seek(
                        Duration(
                          milliseconds: (player.position.inMilliseconds - 10000)
                              .clamp(0, player.duration.inMilliseconds)
                              .toInt(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  Container(
                    height: 60,
                    width: 60,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFC9ABFF),
                    ),
                    child: IconButton(
                      color: const Color(0xFF20192F),
                      iconSize: 34,
                      onPressed: () => unawaited(
                        player.playing ? player.pause() : player.play(),
                      ),
                      icon: Icon(
                        player.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '前进 10 秒',
                    iconSize: 32,
                    onPressed: () => unawaited(
                      player.seek(
                        Duration(
                          milliseconds: (player.position.inMilliseconds + 10000)
                              .clamp(0, player.duration.inMilliseconds)
                              .toInt(),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                  IconButton(
                    tooltip: '字幕校准',
                    onPressed: _offsetSettings,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final showVideo = _item.kind == MediaKind.video;
    final sideBySide =
        showVideo && size.width > size.height && size.width >= 850;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              showVideo ? '视频 · 点击字幕跳转' : '音频 · 点击歌词跳转',
              style: const TextStyle(fontSize: 11, color: Color(0xFF9692A6)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '字幕字体大小',
            onPressed: _fontSettings,
            icon: const Icon(Icons.text_fields_rounded),
          ),
          IconButton(
            tooltip: '导入/替换歌词字幕',
            onPressed: _subtitleBusy ? null : _chooseSubtitle,
            icon: const Icon(Icons.subtitles_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _chooseSubtitle,
                        child: const Text('重新导入字幕'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: sideBySide
                        ? Row(
                            children: [
                              Expanded(flex: 5, child: Center(child: _video())),
                              Expanded(flex: 4, child: _lyricsArea()),
                            ],
                          )
                        : Column(
                            children: [
                              if (showVideo)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: size.height * .38,
                                  ),
                                  child: Center(child: _video()),
                                ),
                              Expanded(child: _lyricsArea()),
                            ],
                          ),
                  ),
                  _controls(),
                ],
              ),
      ),
    );
  }
}
