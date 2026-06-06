import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/playlists/application/playlist_controller.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist_repository.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

AudioSource _source(String id) => AudioSource(
  id: id,
  kind: AudioSourceKind.localFile,
  displayName: '$id.wav',
  reference: '/music/$id.wav',
);

class _FakeRepo implements PlaylistRepository {
  final List<Playlist> _store = [];

  @override
  Future<List<Playlist>> loadAll() async => List.from(_store);

  @override
  Future<void> saveAll(List<Playlist> playlists) async {
    _store
      ..clear()
      ..addAll(playlists);
  }
}

PlaylistController _controller() => PlaylistController(repository: _FakeRepo());

void main() {
  test('starts empty before load', () {
    final c = _controller();
    expect(c.playlists, isEmpty);
    expect(c.selectedId, isNull);
    c.dispose();
  });

  test('loads persisted playlists from repo', () async {
    final repo = _FakeRepo();
    final existing = Playlist(
      id: 'p1',
      name: 'Saved',
      tracks: [],
      createdAt: DateTime(2026),
    );
    await repo.saveAll([existing]);

    final c = PlaylistController(repository: repo);
    await c.load();

    expect(c.playlists, hasLength(1));
    expect(c.playlists.first.name, 'Saved');
    c.dispose();
  });

  test('create adds playlist, selects it, and persists', () async {
    final repo = _FakeRepo();
    final c = PlaylistController(repository: repo);
    await c.load();

    final playlist = await c.create('Morning');

    expect(c.playlists, hasLength(1));
    expect(playlist.name, 'Morning');
    expect(c.selectedId, playlist.id);
    expect(c.selectedPlaylist, isNotNull);

    final reloaded = await repo.loadAll();
    expect(reloaded.first.name, 'Morning');

    c.dispose();
  });

  test('rename updates playlist name', () async {
    final c = _controller();
    final p = await c.create('Old name');
    await c.rename(p.id, 'New name');

    expect(c.playlists.first.name, 'New name');
    c.dispose();
  });

  test('delete removes playlist and clears selection', () async {
    final c = _controller();
    final p = await c.create('Temp');
    expect(c.selectedId, p.id);

    await c.delete(p.id);

    expect(c.playlists, isEmpty);
    expect(c.selectedId, isNull);
    c.dispose();
  });

  test(
    'delete selects last remaining playlist after deleting selected',
    () async {
      final c = _controller();
      final p1 = await c.create('First');
      final p2 = await c.create('Second');
      c.select(p1.id);
      expect(c.selectedId, p1.id);

      await c.delete(p1.id);

      expect(c.selectedId, p2.id);
      c.dispose();
    },
  );

  test('addTracks appends tracks and preserves order', () async {
    final c = _controller();
    final p = await c.create('Nature');

    await c.addTracks(p.id, [_source('rain'), _source('wind')]);

    final tracks = c.selectedPlaylist!.tracks;
    expect(tracks, hasLength(2));
    expect(tracks[0].source.id, 'rain');
    expect(tracks[1].source.id, 'wind');
    c.dispose();
  });

  test('removeTrack removes only the specified track', () async {
    final c = _controller();
    final p = await c.create('Mix');
    await c.addTracks(p.id, [_source('a'), _source('b'), _source('c')]);
    final tracks = c.selectedPlaylist!.tracks;
    final middleId = tracks[1].id;

    await c.removeTrack(p.id, middleId);

    final remaining = c.selectedPlaylist!.tracks;
    expect(remaining, hasLength(2));
    expect(remaining.map((t) => t.source.id), ['a', 'c']);
    c.dispose();
  });

  test('reorderTrack moves a track to a new position', () async {
    final c = _controller();
    final p = await c.create('Shuffle');
    await c.addTracks(p.id, [_source('a'), _source('b'), _source('c')]);

    // newIndex is the final target index (onReorderItem semantics).
    await c.reorderTrack(p.id, oldIndex: 0, newIndex: 2);

    expect(c.selectedPlaylist!.tracks.map((t) => t.source.id), ['b', 'c', 'a']);
    c.dispose();
  });
}
