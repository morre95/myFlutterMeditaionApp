import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/domain/audio_source.dart';

/// Persists user preferences that are shared across the app — currently the
/// library of custom timer bells the user has added.
abstract interface class AppSettingsRepository {
  Future<List<AudioSource>> loadCustomBells();

  Future<void> saveCustomBells(List<AudioSource> bells);
}

class SharedPreferencesAppSettingsRepository implements AppSettingsRepository {
  static const _customBellsKey = 'app_settings_custom_bells_v1';

  @override
  Future<List<AudioSource>> loadCustomBells() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customBellsKey);
    if (raw == null) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => AudioSource.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveCustomBells(List<AudioSource> bells) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(bells.map((b) => b.toJson()).toList());
    await prefs.setString(_customBellsKey, encoded);
  }
}
