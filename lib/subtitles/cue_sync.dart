import '../models/timed_cue.dart';

/// Subtitle time = media time - offset. A positive offset delays lyrics.
class CueSync {
  const CueSync();

  int activeIndex(List<TimedCue> cues, Duration mediaPosition, {int offsetMs = 0}) {
    if (cues.isEmpty) return -1;
    final value = mediaPosition.inMilliseconds - offsetMs;
    var low = 0;
    var high = cues.length - 1;
    var candidate = -1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (cues[middle].start.inMilliseconds <= value) {
        candidate = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    if (candidate == -1 || value >= cues[candidate].end.inMilliseconds) return -1;
    return candidate;
  }

  Duration jumpTime(TimedCue cue, {int offsetMs = 0}) => Duration(
    milliseconds: (cue.start.inMilliseconds + offsetMs).clamp(0, 2147483647),
  );
}
