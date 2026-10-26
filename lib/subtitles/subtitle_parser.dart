import '../models/timed_cue.dart';

/// Extension point: add ASS, word-level lyrics, AI transcripts without touching UI.
abstract interface class TimedTextParser {
  Set<String> get extensions;
  List<TimedCue> parse(String source);
}

class SubtitleParsers {
  SubtitleParsers({Iterable<TimedTextParser>? extra}) {
    register(LrcParser());
    register(SubtitleBlockParser());
    register(AssParser());
    for (final parser in extra ?? <TimedTextParser>[]) {
      register(parser);
    }
  }

  final Map<String, TimedTextParser> _parsers = {};

  void register(TimedTextParser parser) {
    for (final extension in parser.extensions) {
      _parsers[extension.toLowerCase()] = parser;
    }
  }

  List<TimedCue> parse(String extension, String input) {
    final parser = _parsers[extension.toLowerCase().replaceFirst('.', '')];
    if (parser == null) {
      throw FormatException('暂不支持 .$extension 字幕格式');
    }
    final result = parser.parse(input.replaceFirst('\uFEFF', ''));
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }
}

class LrcParser implements TimedTextParser {
  @override
  Set<String> get extensions => const {'lrc'};

  static final _time = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _offset = RegExp(
    r'\[offset:\s*([+-]?\d+)\s*\]',
    caseSensitive: false,
  );

  @override
  List<TimedCue> parse(String source) {
    final result = <TimedCue>[];
    final offset =
        int.tryParse(_offset.firstMatch(source)?.group(1) ?? '') ?? 0;
    for (final line in source.replaceAll('\r\n', '\n').split('\n')) {
      final stamps = _time.allMatches(line).toList();
      if (stamps.isEmpty) continue;
      final text = line.replaceAll(_time, '').trim();
      if (text.isEmpty) continue;
      for (final stamp in stamps) {
        final minutes = int.parse(stamp.group(1)!);
        final seconds = int.parse(stamp.group(2)!);
        final fraction = stamp.group(3) ?? '';
        final ms = fraction.isEmpty ? 0 : int.parse(fraction.padRight(3, '0'));
        final t = ((minutes * 60 + seconds) * 1000 + ms + offset)
            .clamp(0, 2147483647)
            .toInt();
        result.add(
          TimedCue(
            start: Duration(milliseconds: t),
            end: Duration(milliseconds: t),
            text: text,
          ),
        );
      }
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return [
      for (var i = 0; i < result.length; i++)
        TimedCue(
          start: result[i].start,
          end: i + 1 < result.length
              ? result[i + 1].start
              : const Duration(days: 1),
          text: result[i].text,
        ),
    ];
  }
}

/// Parses SRT and WebVTT. V1 supports cue timestamps, multiline text,
/// voice/formatting tag stripping, and WebVTT cue identifiers.
class SubtitleBlockParser implements TimedTextParser {
  @override
  Set<String> get extensions => const {'srt', 'vtt'};

  @override
  List<TimedCue> parse(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n\s*\n'));
    final cues = <TimedCue>[];
    for (final block in blocks) {
      final lines = block.split('\n');
      final timeIndex = lines.indexWhere((line) => line.contains('-->'));
      if (timeIndex < 0) continue;
      final timeParts = lines[timeIndex].split('-->');
      if (timeParts.length != 2) continue;
      final start = _parseClock(timeParts[0].trim());
      // WebVTT end time may have position/alignment settings after the time.
      final end = _parseClock(timeParts[1].trim().split(RegExp(r'\s+')).first);
      if (start == null || end == null || end <= start) continue;
      final text = lines
          .skip(timeIndex + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      if (text.isEmpty) continue;
      cues.add(TimedCue(start: start, end: end, text: _unescape(text)));
    }
    return cues;
  }

  Duration? _parseClock(String s) {
    final parts = s.replaceAll(',', '.').split(':');
    if (parts.length != 2 && parts.length != 3) return null;
    final secParts = parts.last.split('.');
    if (secParts.length != 2 || secParts[1].isEmpty || secParts[1].length > 3) {
      return null;
    }
    final seconds = int.tryParse(secParts[0]);
    final ms = int.tryParse(secParts[1].padRight(3, '0'));
    final minutes = int.tryParse(parts[parts.length - 2]);
    final hours = parts.length == 3 ? int.tryParse(parts[0]) : 0;
    if (seconds == null ||
        seconds > 59 ||
        minutes == null ||
        minutes > 59 ||
        ms == null ||
        hours == null) {
      return null;
    }
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: ms,
    );
  }

  String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
}

/// Parses the timing and plain-text portion of Advanced SubStation Alpha (.ass).
/// Styling, positioning, karaoke effects and vector drawings are intentionally ignored.
class AssParser implements TimedTextParser {
  @override
  Set<String> get extensions => const {'ass'};

  static final _timestamp = RegExp(r'^(\d+):(\d{2}):(\d{2})[.,](\d{1,3})$');

  @override
  List<TimedCue> parse(String source) {
    final lines = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    List<String> format = const [
      'layer',
      'start',
      'end',
      'style',
      'name',
      'marginl',
      'marginr',
      'marginv',
      'effect',
      'text',
    ];
    final cues = <TimedCue>[];
    var inEvents = false;
    var sawSection = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith(';')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        sawSection = true;
        inEvents = line.toLowerCase() == '[events]';
        continue;
      }
      if (line.toLowerCase().startsWith('format:')) {
        if (!sawSection || inEvents) {
          format = line
              .substring(line.indexOf(':') + 1)
              .split(',')
              .map((field) => field.trim().toLowerCase())
              .toList();
        }
        continue;
      }
      if (!line.toLowerCase().startsWith('dialogue:') ||
          (sawSection && !inEvents)) {
        continue;
      }

      final fields = _splitFields(
        line.substring(line.indexOf(':') + 1),
        format.length,
      );
      final startIndex = format.indexOf('start');
      final endIndex = format.indexOf('end');
      final textIndex = format.indexOf('text');
      if (startIndex < 0 ||
          endIndex < 0 ||
          textIndex < 0 ||
          fields.length <= startIndex ||
          fields.length <= endIndex ||
          fields.length <= textIndex) {
        continue;
      }
      final start = _parseAssTime(fields[startIndex].trim());
      final end = _parseAssTime(fields[endIndex].trim());
      if (start == null || end == null || end <= start) continue;

      final text = fields[textIndex]
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\h', ' ')
          .trim();
      if (text.isEmpty) continue;
      cues.add(TimedCue(start: start, end: end, text: text));
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  List<String> _splitFields(String line, int expectedFields) {
    if (expectedFields <= 1) return [line];
    final fields = <String>[];
    var fieldStart = 0;
    for (
      var i = 0;
      i < line.length && fields.length < expectedFields - 1;
      i++
    ) {
      if (line.codeUnitAt(i) == 44) {
        fields.add(line.substring(fieldStart, i).trim());
        fieldStart = i + 1;
      }
    }
    fields.add(line.substring(fieldStart).trim());
    return fields;
  }

  Duration? _parseAssTime(String value) {
    final match = _timestamp.firstMatch(value);
    if (match == null) return null;
    final hours = int.tryParse(match.group(1)!);
    final minutes = int.tryParse(match.group(2)!);
    final seconds = int.tryParse(match.group(3)!);
    final fraction = int.tryParse(match.group(4)!.padRight(3, '0'));
    if (hours == null ||
        minutes == null ||
        minutes > 59 ||
        seconds == null ||
        seconds > 59 ||
        fraction == null) {
      return null;
    }
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: fraction,
    );
  }
}
