import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/bell_selection.dart';
import '../domain/timer_settings.dart';

/// Persists the last-used timer duration and bell selection.
abstract interface class TimerSettingsRepository {
  Future<TimerSettings?> load();

  Future<void> save(TimerSettings settings);
}

class SharedPreferencesTimerSettingsRepository
    implements TimerSettingsRepository {
  static const _key = 'timer_settings_v1';

  @override
  Future<TimerSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    final json = jsonDecode(raw) as Map<String, dynamic>;
    return TimerSettings(
      duration: Duration(minutes: json['durationMinutes'] as int),
      bell: BellSelection.fromJson(json['bell'] as Map<String, dynamic>),
    );
  }

  @override
  Future<void> save(TimerSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      'durationMinutes': settings.duration.inMinutes,
      'bell': settings.bell.toJson(),
    });
    await prefs.setString(_key, encoded);
  }
}
