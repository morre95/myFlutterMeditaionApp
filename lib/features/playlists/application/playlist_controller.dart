import 'package:flutter/foundation.dart';

import '../../../shared/domain/audio_source.dart';
import '../domain/playlist.dart';
import '../domain/playlist_repository.dart';

/// Manages all saved playlists and tracks which one is selected.
///
/// Call [load] once at startup to restore persisted playlists.
class PlaylistController extends ChangeNotifier {
  PlaylistController({required PlaylistRepository repository})
    : _repository = repository;

  final PlaylistRepository _repository;

  List<Playlist> _playlists = [];
  String? _selectedId;
  int _nextId = 0;
  int _nextTrackId = 0;
  bool _isLoading = false;

  List<Playlist> get playlists => List<Playlist>.unmodifiable(_playlists);
  String? get selectedId => _selectedId;
  bool get isLoading => _isLoading;

  Playlist? get selectedPlaylist {
    if (_selectedId == null) return null;
    for (final p in _playlists) {
      if (p.id == _selectedId) return p;
    }
    return null;
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _playlists = await _repository.loadAll();
    _isLoading = false;
    notifyListeners();
  }

  Future<Playlist> create(String name) async {
    final playlist = Playlist(
      id: 'playlist-${_nextId++}',
      name: name,
      tracks: [],
      createdAt: DateTime.now(),
    );
    _playlists.add(playlist);
    _selectedId = playlist.id;
    await _persist();
    return playlist;
  }

  Future<void> rename(String playlistId, String name) async {
    final index = _indexOf(playlistId);
    if (index < 0) return;
    _playlists[index] = _playlists[index].copyWith(name: name);
    await _persist();
  }

  Future<void> delete(String playlistId) async {
    _playlists.removeWhere((p) => p.id == playlistId);
    if (_selectedId == playlistId) {
      _selectedId = _playlists.isNotEmpty ? _playlists.last.id : null;
    }
    await _persist();
  }

  void select(String playlistId) {
    if (_selectedId == playlistId) return;
    _selectedId = playlistId;
    notifyListeners();
  }

  Future<List<PlaylistTrack>> addTracks(
    String playlistId,
    Iterable<AudioSource> sources,
  ) async {
    final index = _indexOf(playlistId);
    if (index < 0) return [];

    final newTracks = sources
        .map((s) => PlaylistTrack(id: 'track-${_nextTrackId++}', source: s))
        .toList(growable: false);

    if (newTracks.isEmpty) return [];

    final updated = List<PlaylistTrack>.from(_playlists[index].tracks)
      ..addAll(newTracks);
    _playlists[index] = _playlists[index].copyWith(tracks: updated);
    await _persist();
    return newTracks;
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    final index = _indexOf(playlistId);
    if (index < 0) return;

    final updated = _playlists[index].tracks
        .where((t) => t.id != trackId)
        .toList();
    _playlists[index] = _playlists[index].copyWith(tracks: updated);
    await _persist();
  }

  Future<void> reorderTrack(
    String playlistId, {
    required int oldIndex,
    required int newIndex,
  }) async {
    final index = _indexOf(playlistId);
    if (index < 0) return;

    final tracks = List<PlaylistTrack>.from(_playlists[index].tracks);
    if (oldIndex < 0 || oldIndex >= tracks.length) return;
    if (newIndex < 0 || newIndex > tracks.length) return;

    final track = tracks.removeAt(oldIndex);
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    tracks.insert(adjusted, track);
    _playlists[index] = _playlists[index].copyWith(tracks: tracks);
    await _persist();
  }

  int _indexOf(String playlistId) =>
      _playlists.indexWhere((p) => p.id == playlistId);

  Future<void> _persist() async {
    await _repository.saveAll(_playlists);
    notifyListeners();
  }
}
