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
  final _cueListKey = GlobalKey<CueListState>();
  late MediaEntry _item = widget.initialItem;
  MediaPlayback? _player;
  List<TimedCue> _cues = [];
  int _activeIndex = -1;
  bool _follow = true;
  bool _loading = true;
  bool _subtitleBusy = false;
  double? _scrubMs;
  String? _error;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
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
    await widget.repository.upsert(_item);
  }

  void _offsetSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final value = _item.subtitleOffsetMs;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '调整字幕时间',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${value >= 0 ? '+' : ''}${(value / 1000).toStringAsFixed(2)} 秒',
                    style: const TextStyle(
                      fontSize: 25,
                      color: Color(0xFFC9ABFF),
                    ),
                  ),
                  const Text(
                    '正值：字幕延后；负值：字幕提前',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9691A4)),
                  ),
                  Slider(
                    value: value.clamp(-5000, 5000).toDouble(),
                    min: -5000,
                    max: 5000,
                    divisions: 40,
                    onChanged: (changed) {
                      setLocalState(() {});
                      unawaited(_updateOffset(changed.round()));
                    },
                  ),
                  TextButton.icon(
                    onPressed: () {
                      unawaited(_updateOffset(0));
                      setLocalState(() {});
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('恢复 0 秒'),
                  ),
                ],
              ),
            ),
          );
        },
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
        final value = (_scrubMs ?? currentMs).clamp(0.0, sliderMax);
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
                              .clamp(0, player.duration.inMilliseconds),
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
                              .clamp(0, player.duration.inMilliseconds),
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
