import 'package:shared_preferences/shared_preferences.dart';

/// User preferences kept separate from the media library so settings can grow
/// without changing the media-entry persistence format.
class AppSettingsRepository {
  static const _subtitleFontSizeKey = 'lyricflow.subtitleFontSize.v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<double> loadSubtitleFontSize() async =>
      await _preferences.getDouble(_subtitleFontSizeKey) ?? 22.0;

  Future<void> saveSubtitleFontSize(double value) => _preferences.setDouble(
    _subtitleFontSizeKey,
    value.clamp(14.0, 36.0).toDouble(),
  );
}
