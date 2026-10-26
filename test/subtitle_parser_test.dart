import 'package:flutter_test/flutter_test.dart';
import 'package:lyricflow/subtitles/cue_sync.dart';
import 'package:lyricflow/subtitles/subtitle_parser.dart';

void main() {
  final parsers = SubtitleParsers();
  const sync = CueSync();

  test('LRC parses centiseconds and repeated timestamps', () {
    final cues = parsers.parse('lrc', '''
[00:01.50][00:03.00]Hello
[00:05.123]World
''');
    expect(cues.length, 3);
    expect(cues[0].start.inMilliseconds, 1500);
    expect(cues[1].start.inMilliseconds, 3000);
    expect(cues[2].start.inMilliseconds, 5123);
    expect(cues[0].end.inMilliseconds, 3000);
  });

  test('LRC offset applies to timestamps', () {
    final cues = parsers.parse('lrc', '[offset:+500]\n[00:03.00]Hi');
    expect(cues.single.start.inMilliseconds, 3500);
  });

  test('SRT handles cues, tags and multiline text', () {
    final cues = parsers.parse('srt', '''
1
00:00:01,200 --> 00:00:03,300
<b>Hello</b>
world

2
00:00:05,000 --> 00:00:06,000
Goodbye
''');
    expect(cues.length, 2);
    expect(cues[0].text, 'Hello\nworld');
    expect(cues[1].start.inMilliseconds, 5000);
    expect(sync.activeIndex(cues, const Duration(milliseconds: 4100)), -1);
  });

  test('VTT supports short timestamps and cue settings', () {
    final cues = parsers.parse('vtt', '''
WEBVTT

my-id
00:01.500 --> 00:03.250 align:start
<v Alice>Yes &amp; no</v>
''');
    expect(cues.single.text, 'Yes & no');
    expect(cues.single.end.inMilliseconds, 3250);
  });

  test('Tap-to-seek respects subtitle delay', () {
    final cues = parsers.parse('lrc', '[00:10.00]Line 1\n[00:13.00]Line 2');
    expect(
      sync.activeIndex(cues, const Duration(seconds: 11), offsetMs: 1000),
      0,
    );
    expect(sync.jumpTime(cues[1], offsetMs: 1000).inSeconds, 14);
  });

  test('ASS parses custom event format, commas and line breaks', () {
    final cues = parsers.parse('ass', r'''[Script Info]
Title: Test
[V4+ Styles]
Format: Name, Fontname
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.25,0:00:03.50,Default,,0,0,0,,Hello, world!
Dialogue: 0,0:00:04.00,0:00:05.25,Default,,0,0,0,,First line\NSecond line {\i1}italic{\i0}
''');
    expect(cues.length, 2);
    expect(cues.first.start.inMilliseconds, 1250);
    expect(cues.first.end.inMilliseconds, 3500);
    expect(cues.first.text, 'Hello, world!');
    expect(cues.last.text, 'First line\nSecond line italic');
  });
}
