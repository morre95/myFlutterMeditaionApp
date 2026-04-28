import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

AudioSource _source(String id) => AudioSource(
  id: id,
  kind: AudioSourceKind.localFile,
  displayName: '$id.wav',
  reference: '/music/$id.wav',
);

void main() {
  group('PlaylistTrack serialization', () {
    test('round-trips through JSON', () {
      final track = PlaylistTrack(id: 'track-1', source: _source('rain'));
      final json = track.toJson();
      final restored = PlaylistTrack.fromJson(json);

      expect(restored.id, track.id);
      expect(restored.source.id, track.source.id);
      expect(restored.source.reference, track.source.reference);
      expect(restored.source.displayName, track.source.displayName);
    });
  });

  group('Playlist serialization', () {
    test('round-trips through JSON with multiple tracks', () {
      final playlist = Playlist(
        id: 'p1',
        name: 'Morning flow',
        tracks: [
          PlaylistTrack(id: 't1', source: _source('rain')),
          PlaylistTrack(id: 't2', source: _source('forest')),
        ],
        createdAt: DateTime.utc(2026, 1, 15, 8),
      );

      final json = playlist.toJson();
      final restored = Playlist.fromJson(json);

      expect(restored.id, playlist.id);
      expect(restored.name, playlist.name);
      expect(restored.createdAt, playlist.createdAt);
      expect(restored.tracks, hasLength(2));
      expect(restored.tracks[0].id, 't1');
      expect(restored.tracks[1].source.reference, '/music/forest.wav');
    });

    test('copyWith updates name and tracks independently', () {
      final original = Playlist(
        id: 'p1',
        name: 'Old',
        tracks: [],
        createdAt: DateTime(2026),
      );

      final renamed = original.copyWith(name: 'New');
      expect(renamed.name, 'New');
      expect(renamed.id, 'p1');

      final withTracks = original.copyWith(
        tracks: [PlaylistTrack(id: 't1', source: _source('rain'))],
      );
      expect(withTracks.tracks, hasLength(1));
      expect(withTracks.name, 'Old');
    });
  });

  group('AudioSource serialization', () {
    test('round-trips through JSON with duration', () {
      const source = AudioSource(
        id: 'rain',
        kind: AudioSourceKind.localFile,
        displayName: 'rain.wav',
        reference: '/music/rain.wav',
        duration: Duration(seconds: 90),
      );

      final json = source.toJson();
      final restored = AudioSource.fromJson(json);

      expect(restored.id, source.id);
      expect(restored.kind, source.kind);
      expect(restored.displayName, source.displayName);
      expect(restored.reference, source.reference);
      expect(restored.duration, source.duration);
    });

    test('round-trips through JSON without duration', () {
      const source = AudioSource(
        id: 'rain',
        kind: AudioSourceKind.localFile,
        displayName: 'rain.wav',
        reference: '/music/rain.wav',
      );

      final restored = AudioSource.fromJson(source.toJson());
      expect(restored.duration, isNull);
    });
  });
}
