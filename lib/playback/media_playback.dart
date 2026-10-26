import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Core playback facade. Future providers can stream, cast, loop, or do A/B repeat.
abstract class MediaPlayback extends ChangeNotifier {
  Duration get position;
  Duration get duration;
  bool get playing;
  bool get initialized;
  double get speed;
  VideoPlayerController? get videoController => null;

  Future<void> open(String localPath);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
}
