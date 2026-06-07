import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/domain/audio_source.dart';

/// Persists user preferences that are shared across the app — the library of
/// custom timer bells the user has added and the set of preinstalled bells they
/// have disabled.
abstract interface class AppSettingsRepository {
  Future<List<AudioSource>> loadCustomBells();

  Future<void> saveCustomBells(List<AudioSource> bells);

  Future<Set<String>> loadDisabledBuiltInBells();

  Future<void> saveDisabledBuiltInBells(Set<String> bellIds);
}

class SharedPreferencesAppSettingsRepository implements AppSettingsRepository {
  static const _customBellsKey = 'app_settings_custom_bells_v1';
  static const _disabledBuiltInBellsKey =
      'app_settings_disabled_builtin_bells_v1';

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

  @override
  Future<Set<String>> loadDisabledBuiltInBells() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_disabledBuiltInBellsKey);
    if (raw == null) return {};

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => e as String).toSet();
  }

  @override
  Future<void> saveDisabledBuiltInBells(Set<String> bellIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_disabledBuiltInBellsKey, jsonEncode(bellIds.toList()));
  }
}
