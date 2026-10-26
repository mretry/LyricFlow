import 'package:flutter_test/flutter_test.dart';
import 'package:lyricflow/models/media_entry.dart';

void main() {
  test('media metadata JSON roundtrip preserves subtitle delay', () {
    final item = MediaEntry(
      id: 'a',
      title: 'Test',
      kind: MediaKind.video,
      mediaPath: 'media/a/original.mp4',
      createdAt: DateTime.utc(2026, 10, 26),
      subtitleOffsetMs: -250,
    );
    final decoded = MediaEntry.fromJson(item.toJson());
    expect(decoded.kind, MediaKind.video);
    expect(decoded.subtitleOffsetMs, -250);
    expect(decoded.mediaPath, 'media/a/original.mp4');
  });
}
