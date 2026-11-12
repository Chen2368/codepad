import 'package:shared_preferences/shared_preferences.dart';

import 'settings_store.dart';

/// 基于 shared_preferences 的设置存储（真机 / 桌面使用）。
class PrefsSettingsStore implements SettingsStore {
  PrefsSettingsStore(this._prefs);

  static const String _key = 'codepad.settings';

  final SharedPreferences _prefs;

  @override
  Future<Map<String, Object?>> readAll() async {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return <String, Object?>{};
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final String pair in raw.split('|')) {
      final int index = pair.indexOf('=');
      if (index <= 0) {
        continue;
      }
      result[pair.substring(0, index)] = pair.substring(index + 1);
    }
    return result;
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    final Map<String, Object?> merged = <String, Object?>{};
    merged.addAll(await readAll());
    merged.addAll(values);
    final String raw = merged.entries
        .where((MapEntry<String, Object?> e) => e.value != null)
        .map((MapEntry<String, Object?> e) => '${e.key}=${e.value}')
        .join('|');
    await _prefs.setString(_key, raw);
  }
}
