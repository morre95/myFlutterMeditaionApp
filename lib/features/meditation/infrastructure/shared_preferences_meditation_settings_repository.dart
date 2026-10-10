import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/domain/audio_source.dart';
import '../../timer/domain/bell_selection.dart';
import '../domain/meditation_settings.dart';

/// Persists the last-used Meditate sound, duration, and ending bell.
abstract interface class MeditationSettingsRepository {
  Future<MeditationSettings?> load();

  Future<void> save(MeditationSettings settings);
}

class SharedPreferencesMeditationSettingsRepository
    implements MeditationSettingsRepository {
  static const _key = 'meditation_settings_v1';

  @override
  Future<MeditationSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    final json = jsonDecode(raw) as Map<String, dynamic>;
    final sound = json['sound'] as Map<String, dynamic>?;
    return MeditationSettings(
      sound: sound == null ? null : AudioSource.fromJson(sound),
      duration: Duration(minutes: json['durationMinutes'] as int),
      bell: BellSelection.fromJson(json['bell'] as Map<String, dynamic>),
      isBellEnabled: json['bellEnabled'] as bool,
    );
  }

  @override
  Future<void> save(MeditationSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      if (settings.sound != null) 'sound': settings.sound!.toJson(),
      'durationMinutes': settings.duration.inMinutes,
      'bell': settings.bell.toJson(),
      'bellEnabled': settings.isBellEnabled,
    });
    await prefs.setString(_key, encoded);
  }
}
