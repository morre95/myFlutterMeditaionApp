import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/history/application/history_controller.dart';
import 'package:my_meditation_app/features/history/domain/meditation_session.dart';
import 'package:my_meditation_app/features/history/infrastructure/shared_preferences_session_repository.dart';
import 'package:my_meditation_app/features/player/application/local_audio_playback_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/features/playlists/application/playlist_playback_controller.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

AudioSource _source(String id, {Duration? duration}) => AudioSource(
  id: id,
  kind: AudioSourceKind.localFile,
  displayName: '$id.wav',
  reference: '/music/$id.wav',
  duration: duration,
);

Playlist _playlist(List<String> ids) => Playlist(
  id: 'p1',
  name: 'Test',
  tracks: ids
      .map((id) => PlaylistTrack(id: 'track-$id', source: _source(id)))
      .toList(),
  createdAt: DateTime(2026),
);

Playlist _playlistWithDurations(Map<String, Duration> tracks) => Playlist(
  id: 'p1',
  name: 'Test',
  tracks: tracks.entries
      .map(
        (e) => PlaylistTrack(
          id: 'track-${e.key}',
          source: _source(e.key, duration: e.value),
        ),
      )
      .toList(),
  createdAt: DateTime(2026),
);

class _FakeSessionRepository implements SessionRepository {
  List<MeditationSession> saved = [];

  @override
  Future<List<MeditationSession>> loadAll() async => List.from(saved);

  @override
  Future<void> saveAll(List<MeditationSession> sessions) async {
    saved = List.from(sessions);
  }
}

class _FakeLocalAudioPlayer implements LocalAudioPlayer {
  final StreamController<bool> _completedController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  String? loadedPath;
  int loadCount = 0;
  int playCount = 0;
  int stopCount = 0;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Future<void> load(PlayableMedia media) async {
    loadCount++;
    loadedPath = media.locator;
  }

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {
    stopCount++;
  }

  void complete() => _completedController.add(true);

  @override
  void dispose() {
    unawaited(_completedController.close());
    unawaited(_positionController.close());
    unawaited(_durationController.close());
  }
}

void main() {
  test('plays first track when playPlaylist is called', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final controller = PlaylistPlaybackController(player: playback);

    await controller.playPlaylist(_playlist(['rain', 'wind']));

    expect(player.loadedPath, '/music/rain.wav');
    expect(controller.state.status, PlaylistPlaybackStatus.playing);
    expect(controller.state.currentTrackIndex, 0);

    controller.dispose();
    playback.dispose();
  });

  test('auto-advances to next track on completion', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final controller = PlaylistPlaybackController(player: playback);

    await controller.playPlaylist(_playlist(['rain', 'forest']));
    expect(player.loadedPath, '/music/rain.wav');

    player.complete();
    await Future<void>.delayed(Duration.zero);

    expect(player.loadedPath, '/music/forest.wav');
    expect(controller.state.currentTrackIndex, 1);
    expect(controller.state.status, PlaylistPlaybackStatus.playing);

    controller.dispose();
    playback.dispose();
  });

  test('playSingleTrack plays only that track and does not advance', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final controller = PlaylistPlaybackController(player: playback);

    await controller.playSingleTrack(_playlist(['rain', 'forest']), 0);
    expect(player.loadedPath, '/music/rain.wav');

    player.complete();
    await Future<void>.delayed(Duration.zero);

    // Stays on the first track and completes instead of advancing to forest.
    expect(player.loadedPath, '/music/rain.wav');
    expect(controller.state.currentTrackIndex, 0);
    expect(controller.state.status, PlaylistPlaybackStatus.completed);

    controller.dispose();
    playback.dispose();
  });

  test('marks completed when last track finishes', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final controller = PlaylistPlaybackController(player: playback);

    await controller.playPlaylist(_playlist(['only']));

    player.complete();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, PlaylistPlaybackStatus.completed);

    controller.dispose();
    playback.dispose();
  });

  test('records a music session when the playlist completes', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final repo = _FakeSessionRepository();
    final history = HistoryController(repository: repo);
    final controller = PlaylistPlaybackController(
      player: playback,
      history: history,
    );

    await controller.playPlaylist(
      _playlistWithDurations({
        'rain': const Duration(minutes: 5),
        'forest': const Duration(minutes: 7),
      }),
    );

    player.complete();
    await Future<void>.delayed(Duration.zero);
    player.complete();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, PlaylistPlaybackStatus.completed);
    expect(history.totalCount, 1);
    expect(history.sessions.single.mode, SessionMode.music);
    // Duration is the sum of the playlist's track durations.
    expect(history.sessions.single.duration, const Duration(minutes: 12));

    controller.dispose();
    playback.dispose();
  });

  test('records a single completed track as a music session', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final repo = _FakeSessionRepository();
    final history = HistoryController(repository: repo);
    final controller = PlaylistPlaybackController(
      player: playback,
      history: history,
    );

    await controller.playSingleTrack(
      _playlistWithDurations({'rain': const Duration(minutes: 5)}),
      0,
    );

    player.complete();
    await Future<void>.delayed(Duration.zero);

    expect(history.totalCount, 1);
    expect(history.sessions.single.mode, SessionMode.music);
    expect(history.sessions.single.duration, const Duration(minutes: 5));

    controller.dispose();
    playback.dispose();
  });

  test('does not record a session for tracks of unknown length', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final repo = _FakeSessionRepository();
    final history = HistoryController(repository: repo);
    final controller = PlaylistPlaybackController(
      player: playback,
      history: history,
    );

    // _playlist builds tracks without durations.
    await controller.playPlaylist(_playlist(['rain']));

    player.complete();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, PlaylistPlaybackStatus.completed);
    expect(history.totalCount, 0);

    controller.dispose();
    playback.dispose();
  });

  test('pause and resume keep track position', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final controller = PlaylistPlaybackController(player: playback);

    await controller.playPlaylist(_playlist(['rain', 'wind']));
    await controller.pause();

    expect(controller.state.status, PlaylistPlaybackStatus.paused);
    expect(controller.state.currentTrackIndex, 0);
    expect(player.loadedPath, '/music/rain.wav');
    expect(player.loadCount, 1);

    await controller.resume();

    expect(controller.state.status, PlaylistPlaybackStatus.playing);
    expect(player.loadedPath, '/music/rain.wav');
    expect(player.loadCount, 1);
    expect(player.playCount, 2);

    controller.dispose();
    playback.dispose();
  });

  test('stop resets state to idle', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final controller = PlaylistPlaybackController(player: playback);

    await controller.playPlaylist(_playlist(['rain']));
    await controller.stop();

    expect(controller.state.status, PlaylistPlaybackStatus.idle);
    expect(controller.state.activePlaylist, isNull);

    controller.dispose();
    playback.dispose();
  });

  test('skipToTrack plays the specified track', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final controller = PlaylistPlaybackController(player: playback);

    await controller.playPlaylist(_playlist(['a', 'b', 'c']));
    await controller.skipToTrack(2);

    expect(player.loadedPath, '/music/c.wav');
    expect(controller.state.currentTrackIndex, 2);

    controller.dispose();
    playback.dispose();
  });

  test('does nothing when playPlaylist called with empty playlist', () async {
    final player = _FakeLocalAudioPlayer();
    final playback = LocalAudioPlaybackController(player: player);
    final controller = PlaylistPlaybackController(player: playback);

    await controller.playPlaylist(_playlist([]));

    expect(controller.state.status, PlaylistPlaybackStatus.idle);
    expect(player.loadedPath, isNull);

    controller.dispose();
    playback.dispose();
  });
}
