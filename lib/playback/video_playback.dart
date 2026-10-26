import 'dart:async';
import 'dart:io';

import 'package:video_player/video_player.dart';

import 'media_playback.dart';

class VideoPlayback extends MediaPlayback {
  VideoPlayerController? _controller;
  double _speed = 1;

  @override
  VideoPlayerController? get videoController => _controller;
  @override
  Duration get position => _controller?.value.position ?? Duration.zero;
  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;
  @override
  bool get playing => _controller?.value.isPlaying ?? false;
  @override
  bool get initialized => _controller?.value.isInitialized ?? false;
  @override
  double get speed => _speed;

  void _onChange() => notifyListeners();

  @override
  Future<void> open(String localPath) async {
    final controller = VideoPlayerController.file(File(localPath));
    _controller = controller;
    controller.addListener(_onChange);
    await controller.initialize();
    notifyListeners();
  }

  @override
  Future<void> play() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.duration > Duration.zero &&
        c.value.position >= c.value.duration) {
      await c.seekTo(Duration.zero);
    }
    await c.play();
  }

  @override
  Future<void> pause() async {
    await _controller?.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _controller?.seekTo(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _controller?.setPlaybackSpeed(speed);
    _speed = speed;
    notifyListeners();
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onChange);
      unawaited(controller.dispose());
    }
    super.dispose();
  }
}
