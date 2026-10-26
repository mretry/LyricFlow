import '../models/media_entry.dart';
import 'audio_playback.dart';
import 'media_playback.dart';
import 'video_playback.dart';

/// Replace this factory to use a new codec or streaming playback provider.
abstract interface class PlaybackFactory {
  MediaPlayback create(MediaKind kind);
}

class DefaultPlaybackFactory implements PlaybackFactory {
  @override
  MediaPlayback create(MediaKind kind) =>
      kind == MediaKind.video ? VideoPlayback() : AudioPlayback();
}
