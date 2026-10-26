import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'media_playback.dart';

class AudioPlayback extends MediaPlayback {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _initialized = false;
  double _speed = 1;

  AudioPlayback() {
    _subs.add(_player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    }));
    _subs.add(_player.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    }));
    _subs.add(_player.playerStateStream.listen((state) {
      _playing = state.playing && state.processingState != ProcessingState.completed;
      notifyListeners();
    }));
  }

  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  bool get playing => _playing;
  @override
  bool get initialized => _initialized;
  @override
  double get speed => _speed;

  @override
  Future<void> open(String localPath) async {
    await _player.setFilePath(localPath);
    _initialized = true;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    // Do not await: just_audio's play future completes when playback finishes.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _speed = speed;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}
