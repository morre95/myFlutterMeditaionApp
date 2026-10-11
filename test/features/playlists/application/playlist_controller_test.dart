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

  group('after a restart', () {
    test('create never reuses a persisted playlist id', () async {
      final repo = _FakeRepo();
      final first = PlaylistController(repository: repo);
      await first.load();
      final existing = await first.create('Existing');
      first.dispose();

      final restarted = PlaylistController(repository: repo);
      await restarted.load();
      final created = await restarted.create('New');

      expect(created.id, isNot(existing.id));
      restarted.dispose();
    });

    test('addTracks never reuses a persisted track id', () async {
      final repo = _FakeRepo();
      final first = PlaylistController(repository: repo);
      await first.load();
      final existing = await first.create('Existing');
      final existingTracks = await first.addTracks(existing.id, [
        _source('a'),
        _source('b'),
      ]);
      first.dispose();

      final restarted = PlaylistController(repository: repo);
      await restarted.load();
      final created = await restarted.create('New');
      final newTracks = await restarted.addTracks(created.id, [_source('c')]);
      final extraTracks = await restarted.addTracks(existing.id, [
        _source('d'),
      ]);

      final allIds = [
        ...existingTracks,
        ...newTracks,
        ...extraTracks,
      ].map((t) => t.id);
      expect(allIds.toSet(), hasLength(4));
      restarted.dispose();
    });

    test(
      'removing a track added after restart keeps the persisted tracks',
      () async {
        final repo = _FakeRepo();
        final first = PlaylistController(repository: repo);
        await first.load();
        final playlist = await first.create('Mix');
        await first.addTracks(playlist.id, [_source('a')]);
        first.dispose();

        final restarted = PlaylistController(repository: repo);
        await restarted.load();
        final added = await restarted.addTracks(playlist.id, [_source('b')]);
        await restarted.removeTrack(playlist.id, added.single.id);

        expect(restarted.playlists.single.tracks.map((t) => t.source.id), [
          'a',
        ]);
        restarted.dispose();
      },
    );
  });

  group('loading playlists persisted with duplicate ids', () {
    PlaylistTrack track(String id, String sourceId) =>
        PlaylistTrack(id: id, source: _source(sourceId));

    Future<_FakeRepo> corruptRepo() async {
      final repo = _FakeRepo();
      await repo.saveAll([
        Playlist(
          id: 'playlist-0',
          name: 'Morning',
          tracks: [
            track('track-0', 'a'),
            track('track-1', 'b'),
            track('track-1', 'c'),
          ],
          createdAt: DateTime(2026),
        ),
        Playlist(
          id: 'playlist-0',
          name: 'Evening',
          tracks: [track('track-0', 'd'), track('track-2', 'e')],
          createdAt: DateTime(2026, 2),
        ),
      ]);
      return repo;
    }

    test('gives every playlist and track a unique id', () async {
      final c = PlaylistController(repository: await corruptRepo());
      await c.load();

      final playlistIds = c.playlists.map((p) => p.id);
      final trackIds = c.playlists.expand((p) => p.tracks).map((t) => t.id);
      expect(playlistIds.toSet(), hasLength(2));
      expect(trackIds.toSet(), hasLength(5));
      c.dispose();
    });

    test('keeps every playlist and track in order', () async {
      final c = PlaylistController(repository: await corruptRepo());
      await c.load();

      expect(c.playlists.map((p) => p.name), ['Morning', 'Evening']);
      expect(c.playlists[0].tracks.map((t) => t.source.id), ['a', 'b', 'c']);
      expect(c.playlists[1].tracks.map((t) => t.source.id), ['d', 'e']);
      c.dispose();
    });

    test('the first occurrence keeps its id', () async {
      final c = PlaylistController(repository: await corruptRepo());
      await c.load();

      expect(c.playlists[0].id, 'playlist-0');
      expect(c.playlists[0].tracks.map((t) => t.id).take(2), [
        'track-0',
        'track-1',
      ]);
      expect(c.playlists[1].tracks.last.id, 'track-2');
      c.dispose();
    });

    test('persists the repaired ids', () async {
      final repo = await corruptRepo();
      final c = PlaylistController(repository: repo);
      await c.load();

      final saved = await repo.loadAll();
      expect(saved.map((p) => p.id), c.playlists.map((p) => p.id));
      expect(
        saved.expand((p) => p.tracks).map((t) => t.id),
        c.playlists.expand((p) => p.tracks).map((t) => t.id),
      );
      c.dispose();
    });

    test('removeTrack then removes only the chosen track', () async {
      final c = PlaylistController(repository: await corruptRepo());
      await c.load();
      final second = c.playlists[1];

      await c.removeTrack(second.id, second.tracks.first.id);

      expect(c.playlists[0].tracks.map((t) => t.source.id), ['a', 'b', 'c']);
      expect(c.playlists[1].tracks.map((t) => t.source.id), ['e']);
      c.dispose();
    });
  });
}
