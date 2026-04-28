import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/playlist.dart';
import '../domain/playlist_repository.dart';

class SharedPreferencesPlaylistRepository implements PlaylistRepository {
  static const _key = 'playlists_v1';

  @override
  Future<List<Playlist>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveAll(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(playlists.map((p) => p.toJson()).toList());
    await prefs.setString(_key, encoded);
  }
}
