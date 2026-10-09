import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/history/application/history_controller.dart';
import 'package:my_meditation_app/features/history/domain/meditation_session.dart';
import 'package:my_meditation_app/features/history/infrastructure/shared_preferences_session_repository.dart';
import 'package:my_meditation_app/features/player/application/local_audio_playback_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_ownership_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/features/playlists/application/playlist_playback_controller.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist.dart';
import 'package:my_meditation_app/features/timer/application/timer_bell_player.dart';
import 'package:my_meditation_app/features/timer/application/timer_controller.dart';
import 'package:my_meditation_app/features/timer/application/wake_lock.dart';
import 'package:my_meditation_app/features/timer/domain/bell_selection.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

Playlist _playlist() => Playlist(
  id: 'morning',
  name: 'Morning',
  tracks: [
    PlaylistTrack(
      id: 'rain',
      source: const AudioSource(
        id: 'rain',
        kind: AudioSourceKind.localFile,
        displayName: 'rain.wav',
        reference: '/rain.wav',
        duration: Duration(minutes: 3),
      ),
    ),
  ],
  createdAt: DateTime(2026),
);

void main() {
  test(
    'starting silent Timer stops Music and returning to Music cancels Timer',
    () {
      fakeAsync((async) {
        final ownership = PlaybackOwnershipController();
        final audio = _AudioPlayer();
        final player = LocalAudioPlaybackController(player: audio);
        final music = PlaylistPlaybackController(
          player: player,
          ownership: ownership,
        );
        final bell = _BellPlayer();
        final timer = TimerController(
          bellPlayer: bell,
          wakeLock: _WakeLock(),
          ownership: ownership,
        );
        timer.setDuration(const Duration(minutes: 1));
        music.playPlaylist(_playlist());
        async.flushMicrotasks();
        timer.start();
        async.flushMicrotasks();

        expect(audio.isPlaying, isFalse);
        expect(music.state.status, PlaylistPlaybackStatus.idle);
        expect(timer.state.isRunning, isTrue);
        expect(ownership.activeOwner, same(timer));

        music.playPlaylist(_playlist());
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
        expect(audio.isPlaying, isTrue);
        expect(timer.state.status, TimerSessionStatus.idle);
        expect(bell.isPlaying, isFalse);
        expect(ownership.activeOwner, same(music));

        timer.dispose();
        music.dispose();
        player.dispose();
        async.flushMicrotasks();
      });
    },
  );
  test('a queued ending bell cannot take ownership back from Music', () {
    fakeAsync((async) {
      final ownership = PlaybackOwnershipController();
      final audio = _AudioPlayer();
      final player = LocalAudioPlaybackController(player: audio);
      final music = PlaylistPlaybackController(
        player: player,
        ownership: ownership,
      );
      final bell = _BellPlayer();
      final resolver = _DeferredResolver();
      final timer = TimerController(
        bellPlayer: bell,
        sourceResolver: resolver,
        wakeLock: _WakeLock(),
        ownership: ownership,
      );
      timer.setDuration(const Duration(minutes: 1));
      timer.start();
      async.flushMicrotasks();
      timer.previewBell(
        const BellSelection.custom(
          AudioSource(
            id: 'cloud-gong',
            kind: AudioSourceKind.pCloud,
            displayName: 'Gong',
            reference: '123',
          ),
        ),
      );
      async.flushMicrotasks();
      music.playPlaylist(_playlist());
      async.elapse(const Duration(minutes: 1));
      resolver.result.complete(const PlayableMedia.file('/gong.wav'));
      async.flushMicrotasks();

      expect(audio.isPlaying, isTrue);
      expect(bell.isPlaying, isFalse);
      expect(ownership.activeOwner, same(music));

      timer.dispose();
      music.dispose();
      player.dispose();
      async.flushMicrotasks();
    });
  });

  test(
    'completion from the previous track does not skip a loading replacement',
    () {
      fakeAsync((async) {
        final ownership = PlaybackOwnershipController();
        final audio = _AudioPlayer();
        final resolver = _DeferredResolver();
        final player = LocalAudioPlaybackController(
          player: audio,
          resolver: resolver,
        );
        final music = PlaylistPlaybackController(
          player: player,
          ownership: ownership,
        );
        music.playPlaylist(_playlist());
        async.flushMicrotasks();
        final replacement = Playlist(
          id: 'replacement',
          name: 'Replacement',
          tracks: [
            PlaylistTrack(
              id: 'cloud',
              source: const AudioSource(
                id: 'cloud',
                kind: AudioSourceKind.pCloud,
                displayName: 'cloud.wav',
                reference: '123',
              ),
            ),
            _playlist().tracks.first,
          ],
          createdAt: DateTime(2026),
        );
        music.playPlaylist(replacement);
        async.flushMicrotasks();
        audio.completions.add(true);
        async.flushMicrotasks();
        resolver.result.complete(
          const PlayableMedia.url('https://example.com/cloud.wav'),
        );
        async.flushMicrotasks();

        expect(music.state.currentTrack?.id, 'cloud');
        expect(player.state.status, LocalPlaybackStatus.playing);

        music.dispose();
        player.dispose();
        async.flushMicrotasks();
      });
    },
  );

  test('a queued old completion cannot advance a newly selected playlist', () {
    fakeAsync((async) {
      final ownership = PlaybackOwnershipController();
      final audio = _AudioPlayer();
      final player = LocalAudioPlaybackController(player: audio);
      final music = PlaylistPlaybackController(
        player: player,
        ownership: ownership,
      );
      music.playPlaylist(_playlist());
      async.flushMicrotasks();
      final replacement = Playlist(
        id: 'replacement',
        name: 'Replacement',
        tracks: [
          _playlist().tracks.first,
          PlaylistTrack(
            id: 'forest',
            source: const AudioSource(
              id: 'forest',
              kind: AudioSourceKind.localFile,
              displayName: 'forest.wav',
              reference: '/forest.wav',
            ),
          ),
        ],
        createdAt: DateTime(2026),
      );
      music.playPlaylist(replacement);
      audio.completions.add(true);
      async.flushMicrotasks();

      expect(music.state.activePlaylist?.id, 'replacement');
      expect(music.state.currentTrack?.id, 'rain');

      music.dispose();
      player.dispose();
      async.flushMicrotasks();
    });
  });

  test('bell previews stop Music and Music stops the previous bell', () async {
    final ownership = PlaybackOwnershipController();
    final audio = _AudioPlayer();
    final player = LocalAudioPlaybackController(player: audio);
    final music = PlaylistPlaybackController(
      player: player,
      ownership: ownership,
    );
    final bell = _BellPlayer();
    final timer = TimerController(
      bellPlayer: bell,
      wakeLock: _WakeLock(),
      ownership: ownership,
    );
    await music.playPlaylist(_playlist());
    await timer.previewBell(const BellSelection.builtIn('bell_2'));
    expect(audio.isPlaying, isFalse);
    expect(bell.isPlaying, isTrue);
    await music.playPlaylist(_playlist());
    expect(bell.isPlaying, isFalse);
    expect(audio.isPlaying, isTrue);
    timer.dispose();
    music.dispose();
    player.dispose();
  });

  test(
    'completion and later media updates record one completed session',
    () async {
      final history = HistoryController(repository: _SessionRepository());
      final audio = _AudioPlayer();
      final player = LocalAudioPlaybackController(player: audio);
      final music = PlaylistPlaybackController(
        player: player,
        history: history,
      );
      await music.playPlaylist(_playlist());
      audio.completions.add(true);
      audio.positions.add(const Duration(minutes: 3));
      audio.durations.add(const Duration(minutes: 3));
      audio.completions.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(history.totalCount, 1);
      music.dispose();
      player.dispose();
      history.dispose();
    },
  );
  test(
    'unavailable Music actions leave an active silent Timer running',
    () async {
      final ownership = PlaybackOwnershipController();
      final audio = _AudioPlayer();
      final player = LocalAudioPlaybackController(player: audio);
      final music = PlaylistPlaybackController(
        player: player,
        ownership: ownership,
      );
      final timer = TimerController(
        bellPlayer: _BellPlayer(),
        wakeLock: _WakeLock(),
        ownership: ownership,
      );
      await timer.start();
      final empty = Playlist(
        id: 'empty',
        name: 'Empty',
        tracks: [],
        createdAt: DateTime(2026),
      );
      await music.playPlaylist(empty);
      await music.resume();
      await music.playSingleTrack(_playlist(), -1);
      await music.skipToTrack(0);
      expect(timer.state.isRunning, isTrue);
      expect(ownership.activeOwner, same(timer));
      expect(audio.isPlaying, isFalse);
      timer.dispose();
      music.dispose();
      player.dispose();
    },
  );
}

class _AudioPlayer implements LocalAudioPlayer {
  final completions = StreamController<bool>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  bool isPlaying = false;
  @override
  Stream<bool> get completedStream => completions.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration> get durationStream => durations.stream;
  @override
  Future<void> load(PlayableMedia media) async {}
  @override
  Future<void> play() async => isPlaying = true;
  @override
  Future<void> pause() async => isPlaying = false;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async => isPlaying = false;
  @override
  void dispose() {
    unawaited(completions.close());
    unawaited(positions.close());
    unawaited(durations.close());
  }
}

class _BellPlayer implements BellPlayer {
  bool isPlaying = false;
  @override
  Future<void> playAsset(String assetPath) async => isPlaying = true;
  @override
  Future<void> playMedia(PlayableMedia media) async => isPlaying = true;
  @override
  Future<void> stop() async => isPlaying = false;
  @override
  void dispose() => isPlaying = false;
}

class _WakeLock implements WakeLock {
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

class _DeferredResolver implements PlaybackSourceResolver {
  final result = Completer<PlayableMedia>();
  @override
  Future<PlayableMedia> resolve(AudioSource source) =>
      source.kind == AudioSourceKind.localFile
      ? Future.value(PlayableMedia.file(source.reference))
      : result.future;
}

class _SessionRepository implements SessionRepository {
  @override
  Future<List<MeditationSession>> loadAll() async => [];
  @override
  Future<void> saveAll(List<MeditationSession> sessions) async {}
}
