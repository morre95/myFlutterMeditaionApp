import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/meditation_session.dart';

abstract interface class SessionRepository {
  Future<List<MeditationSession>> loadAll();

  Future<void> saveAll(List<MeditationSession> sessions);
}

class SharedPreferencesSessionRepository implements SessionRepository {
  static const _key = 'sessions_v1';

  @override
  Future<List<MeditationSession>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => MeditationSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveAll(List<MeditationSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(sessions.map((s) => s.toJson()).toList());
    await prefs.setString(_key, encoded);
  }
}
