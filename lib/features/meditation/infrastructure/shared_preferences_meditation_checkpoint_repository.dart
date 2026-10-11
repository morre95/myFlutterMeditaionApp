import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/meditation_checkpoint.dart';

/// Persists at most one unfinished Meditate session.
abstract interface class MeditationCheckpointRepository {
  Future<MeditationCheckpoint?> load();

  Future<void> save(MeditationCheckpoint checkpoint);

  Future<void> clear();
}

class SharedPreferencesMeditationCheckpointRepository
    implements MeditationCheckpointRepository {
  static const _key = 'meditation_checkpoint_v1';

  @override
  Future<MeditationCheckpoint?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return MeditationCheckpoint.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> save(MeditationCheckpoint checkpoint) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, jsonEncode(checkpoint.toJson()))) {
      throw StateError('Meditation checkpoint was not saved.');
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_key)) {
      throw StateError('Meditation checkpoint was not cleared.');
    }
  }
}
