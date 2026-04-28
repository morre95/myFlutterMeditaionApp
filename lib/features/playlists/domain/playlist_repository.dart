import 'playlist.dart';

abstract interface class PlaylistRepository {
  Future<List<Playlist>> loadAll();

  Future<void> saveAll(List<Playlist> playlists);
}
