import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The persisted favorite ids: favorite playlists and favorite tracks.
class FavoritesData {
  const FavoritesData({required this.playlistIds, required this.trackIds});

  const FavoritesData.empty() : playlistIds = const {}, trackIds = const {};

  final Set<String> playlistIds;
  final Set<String> trackIds;
}

abstract interface class FavoritesRepository {
  Future<FavoritesData> load();

  Future<void> save(FavoritesData data);
}

class SharedPreferencesFavoritesRepository implements FavoritesRepository {
  static const _key = 'favorites_v1';

  @override
  Future<FavoritesData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const FavoritesData.empty();

    final json = jsonDecode(raw) as Map<String, dynamic>;
    return FavoritesData(
      playlistIds: (json['playlists'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toSet(),
      trackIds: (json['tracks'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toSet(),
    );
  }

  @override
  Future<void> save(FavoritesData data) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      'playlists': data.playlistIds.toList(),
      'tracks': data.trackIds.toList(),
    });
    await prefs.setString(_key, encoded);
  }
}
