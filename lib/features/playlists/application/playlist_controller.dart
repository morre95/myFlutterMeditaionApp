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
  int _idSequence = 0;
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
    final loaded = await _repository.loadAll();
    final hasDuplicateIds = _hasDuplicateIds(loaded);
    _playlists = hasDuplicateIds ? _withUniqueIds(loaded) : loaded;
    _isLoading = false;
    notifyListeners();
    if (hasDuplicateIds) await _saveRepairedIds();
  }

  /// Saves the ids repaired by [load].
  ///
  /// A failed write must not abort startup: the repaired playlists are
  /// already in memory, every later [_persist] writes them in full, and the
  /// next launch repairs the still-duplicated stored data again.
  Future<void> _saveRepairedIds() async {
    try {
      await _repository.saveAll(_playlists);
    } on Exception catch (error) {
      debugPrint('Repaired playlist ids could not be stored: $error');
    }
  }

  Future<Playlist> create(String name) async {
    final playlist = Playlist(
      id: _newId('playlist', _playlistIds()),
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

    final takenTrackIds = _trackIds();
    final newTracks = sources
        .map(
          (s) => PlaylistTrack(id: _newId('track', takenTrackIds), source: s),
        )
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
    // [newIndex] is the final target index (already adjusted by the
    // ReorderableListView onReorderItem callback for the removed item).
    if (newIndex < 0 || newIndex >= tracks.length) return;

    final track = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, track);
    _playlists[index] = _playlists[index].copyWith(tracks: tracks);
    await _persist();
  }

  /// Repairs data persisted before ids were unique across restarts.
  ///
  /// The first playlist or track holding an id keeps it; later duplicates
  /// (within or across playlists) get a fresh id. Nothing is dropped or
  /// merged. Ids kept by the first occurrence stay valid for favorites.
  List<Playlist> _withUniqueIds(List<Playlist> loaded) {
    final takenPlaylistIds = {for (final p in loaded) p.id};
    final takenTrackIds = {
      for (final p in loaded)
        for (final t in p.tracks) t.id,
    };
    final seenPlaylistIds = <String>{};
    final seenTrackIds = <String>{};
    return [
      for (final playlist in loaded)
        Playlist(
          id: seenPlaylistIds.add(playlist.id)
              ? playlist.id
              : _newId('playlist', takenPlaylistIds),
          name: playlist.name,
          createdAt: playlist.createdAt,
          tracks: [
            for (final track in playlist.tracks)
              seenTrackIds.add(track.id)
                  ? track
                  : PlaylistTrack(
                      id: _newId('track', takenTrackIds),
                      source: track.source,
                    ),
          ],
        ),
    ];
  }

  bool _hasDuplicateIds(List<Playlist> playlists) {
    final playlistIds = playlists.map((p) => p.id).toList();
    final trackIds = playlists
        .expand((p) => p.tracks)
        .map((t) => t.id)
        .toList();
    return playlistIds.toSet().length != playlistIds.length ||
        trackIds.toSet().length != trackIds.length;
  }

  /// Returns an id that is not in [taken] and adds it there.
  ///
  /// Ids embed the creation time, so they stay unique across restarts and
  /// are not reused after a delete (which would revive stale favorites).
  String _newId(String prefix, Set<String> taken) {
    String id;
    do {
      id = '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';
    } while (!taken.add(id));
    return id;
  }

  Set<String> _playlistIds() => {for (final p in _playlists) p.id};

  Set<String> _trackIds() => {
    for (final p in _playlists)
      for (final t in p.tracks) t.id,
  };

  int _indexOf(String playlistId) =>
      _playlists.indexWhere((p) => p.id == playlistId);

  Future<void> _persist() async {
    await _repository.saveAll(_playlists);
    notifyListeners();
  }
}
