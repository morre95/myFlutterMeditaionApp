import 'package:flutter/foundation.dart';

import '../infrastructure/shared_preferences_favorites_repository.dart';

/// Tracks which playlists and tracks the user has marked as favorites.
class FavoritesController extends ChangeNotifier {
  FavoritesController({required FavoritesRepository repository})
    : _repository = repository;

  final FavoritesRepository _repository;

  final Set<String> _playlistIds = {};
  final Set<String> _trackIds = {};

  bool isPlaylistFavorite(String id) => _playlistIds.contains(id);

  bool isTrackFavorite(String id) => _trackIds.contains(id);

  Future<void> load() async {
    final data = await _repository.load();
    _playlistIds
      ..clear()
      ..addAll(data.playlistIds);
    _trackIds
      ..clear()
      ..addAll(data.trackIds);
    notifyListeners();
  }

  Future<void> togglePlaylist(String id) => _toggle(_playlistIds, id);

  Future<void> toggleTrack(String id) => _toggle(_trackIds, id);

  Future<void> _toggle(Set<String> ids, String id) async {
    if (!ids.remove(id)) ids.add(id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() {
    return _repository.save(
      FavoritesData(playlistIds: {..._playlistIds}, trackIds: {..._trackIds}),
    );
  }
}
