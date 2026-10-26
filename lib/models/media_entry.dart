enum MediaKind { audio, video }

class MediaEntry {
  const MediaEntry({
    required this.id,
    required this.title,
    required this.kind,
    required this.mediaPath,
    required this.createdAt,
    this.subtitlePath,
    this.lastPositionMs = 0,
    this.subtitleOffsetMs = 0,
  });

  final String id;
  final String title;
  final MediaKind kind;

  /// Path relative to the app documents directory; safe across iOS container moves.
  final String mediaPath;
  final String? subtitlePath;
  final DateTime createdAt;
  final int lastPositionMs;

  /// Positive number means the subtitle is shown later than its timestamp.
  final int subtitleOffsetMs;

  MediaEntry copyWith({
    String? title,
    String? subtitlePath,
    bool clearSubtitle = false,
    int? lastPositionMs,
    int? subtitleOffsetMs,
  }) => MediaEntry(
    id: id,
    title: title ?? this.title,
    kind: kind,
    mediaPath: mediaPath,
    subtitlePath: clearSubtitle ? null : (subtitlePath ?? this.subtitlePath),
    createdAt: createdAt,
    lastPositionMs: lastPositionMs ?? this.lastPositionMs,
    subtitleOffsetMs: subtitleOffsetMs ?? this.subtitleOffsetMs,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'mediaPath': mediaPath,
    'subtitlePath': subtitlePath,
    'createdAt': createdAt.toIso8601String(),
    'lastPositionMs': lastPositionMs,
    'subtitleOffsetMs': subtitleOffsetMs,
  };

  factory MediaEntry.fromJson(Map<String, dynamic> data) => MediaEntry(
    id: data['id'] as String,
    title: data['title'] as String,
    kind: (data['kind'] as String) == 'video'
        ? MediaKind.video
        : MediaKind.audio,
    mediaPath: data['mediaPath'] as String,
    subtitlePath: data['subtitlePath'] as String?,
    createdAt: DateTime.parse(data['createdAt'] as String),
    lastPositionMs: (data['lastPositionMs'] as num?)?.toInt() ?? 0,
    subtitleOffsetMs: (data['subtitleOffsetMs'] as num?)?.toInt() ?? 0,
  );
}
