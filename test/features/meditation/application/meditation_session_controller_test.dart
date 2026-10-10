import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/meditation/application/meditation_session_controller.dart';
import 'package:my_meditation_app/features/player/application/local_audio_playback_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_ownership_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/features/playlists/application/playlist_playback_controller.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

const _rain = AudioSource(
  id: 'import:rain',
  kind: AudioSourceKind.localFile,
  displayName: 'rain.wav',
  reference: '/sounds/rain/audio.wav',
  storedSize: 3,
);

class _Harness {
  _Harness(this.async, {PlaybackSourceResolver? resolver, ElapsedClock? clock})
    : audio = _AudioPlayer() {
    player = LocalAudioPlaybackController(player: audio, resolver: resolver);
    session = MeditationSessionController(
      player: player,
      ownership: ownership,
      clock: clock ?? () => async.elapsed,
    );
  }

  final FakeAsync async;
  final _AudioPlayer audio;
  final ownership = PlaybackOwnershipController();
  late final LocalAudioPlaybackController player;
  late final MeditationSessionController session;

  void startWith(AudioSource sound, Duration duration) {
    session.selectSound(sound);
    session.setDuration(duration);
    session.start();
    async.flushMicrotasks();
  }

  void dispose() {
    session.dispose();
    player.dispose();
    async.flushMicrotasks();
  }
}

void main() {
  test('setup starts at 20 minutes and keeps durations within 1-120', () {
    fakeAsync((async) {
      final h = _Harness(async);
      expect(h.session.state.duration, const Duration(minutes: 20));
      expect(h.session.remaining, const Duration(minutes: 20));
      h.session.setDuration(Duration.zero);
      expect(h.session.state.duration, const Duration(minutes: 1));
      h.session.setDuration(const Duration(minutes: 500));
      expect(h.session.state.duration, const Duration(minutes: 120));
      h.dispose();
    });
  });

  test('a started session keeps its duration and sound', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 5));
      h.session.setDuration(const Duration(minutes: 60));
      h.session.selectSound(_rain.copyWith(id: 'import:bird'));
      async.elapse(const Duration(minutes: 5));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.session.state.sound!.id, _rain.id);
      h.dispose();
    });
  });

  test('active time counts only after the sound is ready and playing', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.audio.loadReady = Completer<void>();
      h.startWith(_rain, const Duration(minutes: 20));
      expect(h.session.state.status, MeditationSessionStatus.loading);
      async.elapse(const Duration(seconds: 30));
      expect(h.session.remaining, const Duration(minutes: 20));

      h.audio.loadReady!.complete();
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.running);
      expect(h.audio.isPlaying, isTrue);
      async.elapse(const Duration(minutes: 1));
      expect(h.session.remaining, const Duration(minutes: 19));
      h.dispose();
    });
  });

  test('a longer sound stops at the active-time deadline', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 5));
      async.elapse(
        const Duration(minutes: 5) - const Duration(milliseconds: 1),
      );
      expect(h.audio.isPlaying, isTrue);

      async.elapse(const Duration(milliseconds: 1));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.session.remaining, Duration.zero);
      expect(h.audio.isPlaying, isFalse);
      h.dispose();
    });
  });

  test(
    'a shorter sound repeats until the deadline without counting reloads',
    () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.startWith(_rain, const Duration(minutes: 5));
        async.elapse(const Duration(minutes: 2));
        h.audio.loadReady = Completer<void>();
        h.audio.finishTrack();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(h.session.remaining, const Duration(minutes: 3));

        h.audio.loadReady!.complete();
        async.flushMicrotasks();
        expect(h.audio.loaded, [_rain.reference, _rain.reference]);
        expect(h.audio.isPlaying, isTrue);
        expect(h.session.state.status, MeditationSessionStatus.running);
        async.elapse(const Duration(minutes: 3));
        expect(h.session.state.status, MeditationSessionStatus.completed);
        expect(h.audio.isPlaying, isFalse);
        h.dispose();
      });
    },
  );

  test('Pause holds sound and countdown; Resume continues both', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 10));
      async.elapse(const Duration(minutes: 4));
      h.session.pause();
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.paused);
      expect(h.audio.isPlaying, isFalse);
      async.elapse(const Duration(hours: 1));
      expect(h.session.remaining, const Duration(minutes: 6));

      h.session.resume();
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.running);
      expect(h.audio.isPlaying, isTrue);
      expect(h.audio.loaded, hasLength(1));
      async.elapse(const Duration(minutes: 6));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      h.dispose();
    });
  });

  test('End stops the session and returns to setup', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 10));
      async.elapse(const Duration(minutes: 4));
      h.session.end();
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.setup);
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.remaining, const Duration(minutes: 10));
      async.elapse(const Duration(minutes: 10));
      expect(h.session.state.status, MeditationSessionStatus.setup);
      h.dispose();
    });
  });

  test('pausing during a repeat reload keeps the session silent', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 5));
      async.elapse(const Duration(minutes: 1));
      h.audio.loadReady = Completer<void>();
      h.audio.finishTrack();
      async.flushMicrotasks();
      h.session.pause();
      h.audio.loadReady!.complete();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.state.status, MeditationSessionStatus.paused);

      h.session.resume();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isTrue);
      async.elapse(const Duration(minutes: 1));
      expect(h.session.remaining, const Duration(minutes: 3));
      h.dispose();
    });
  });

  test('a late refresh ends an overdue session instead of extending it', () {
    fakeAsync((async) {
      var now = Duration.zero;
      final h = _Harness(async, clock: () => now);
      h.startWith(_rain, const Duration(minutes: 20));
      now += const Duration(minutes: 20);
      async.elapse(const Duration(seconds: 1));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.audio.isPlaying, isFalse);
      h.dispose();
    });
  });

  test('a missing sound returns to setup with an error and no countdown', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.audio.loadError = const FileSystemException('missing');
      h.startWith(_rain, const Duration(minutes: 10));
      expect(h.session.state.status, MeditationSessionStatus.setup);
      expect(h.session.state.errorMessage, 'Could not play rain.wav.');
      async.elapse(const Duration(minutes: 1));
      expect(h.session.remaining, const Duration(minutes: 10));
      expect(h.audio.isPlaying, isFalse);
      h.dispose();
    });
  });

  test('repeated Start while loading cannot create a second session', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.audio.loadReady = Completer<void>();
      h.startWith(_rain, const Duration(minutes: 10));
      h.session.start();
      h.audio.loadReady!.complete();
      async.flushMicrotasks();
      expect(h.audio.loaded, hasLength(1));
      expect(h.session.state.status, MeditationSessionStatus.running);
      h.dispose();
    });
  });

  test('a load finishing after End cannot revive the session', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.audio.loadReady = Completer<void>();
      h.startWith(_rain, const Duration(minutes: 10));
      h.session.end();
      h.audio.loadReady!.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(h.session.state.status, MeditationSessionStatus.setup);
      expect(h.session.remaining, const Duration(minutes: 10));
      expect(h.audio.isPlaying, isFalse);
      h.dispose();
    });
  });

  test(
    'a sound vanishing before its repeat ends the session with an error',
    () {
      fakeAsync((async) {
        final h = _Harness(async);
        h.startWith(_rain, const Duration(minutes: 10));
        async.elapse(const Duration(minutes: 3));
        h.audio.loadError = const FileSystemException('missing');
        h.audio.finishTrack();
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.setup);
        expect(h.session.state.errorMessage, 'Could not play rain.wav.');
        h.dispose();
      });
    },
  );

  test('Meditate and Music never sound together', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final musicAudio = _AudioPlayer();
      final musicPlayer = LocalAudioPlaybackController(player: musicAudio);
      final music = PlaylistPlaybackController(
        player: musicPlayer,
        ownership: h.ownership,
      );
      music.playPlaylist(_playlist());
      async.flushMicrotasks();
      h.startWith(_rain, const Duration(minutes: 10));
      expect(musicAudio.isPlaying, isFalse);
      expect(h.audio.isPlaying, isTrue);

      music.playPlaylist(_playlist());
      async.flushMicrotasks();
      expect(musicAudio.isPlaying, isTrue);
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.state.status, MeditationSessionStatus.setup);
      async.elapse(const Duration(minutes: 10));
      expect(h.session.remaining, const Duration(minutes: 10));

      music.dispose();
      musicPlayer.dispose();
      h.dispose();
    });
  });

  test('End while Music is still handing off leaves Meditate silent', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final musicAudio = _AudioPlayer()..loadReady = Completer<void>();
      final musicPlayer = LocalAudioPlaybackController(player: musicAudio);
      final music = PlaylistPlaybackController(
        player: musicPlayer,
        ownership: h.ownership,
      );
      music.playPlaylist(_playlist());
      async.flushMicrotasks();
      h.startWith(_rain, const Duration(minutes: 10));
      h.session.end();
      musicAudio.loadReady!.complete();
      async.flushMicrotasks();
      expect(h.audio.loaded, isEmpty);
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.state.status, MeditationSessionStatus.setup);

      music.dispose();
      musicPlayer.dispose();
      h.dispose();
    });
  });
}

Playlist _playlist() => Playlist(
  id: 'morning',
  name: 'Morning',
  createdAt: DateTime(2026),
  tracks: [
    PlaylistTrack(
      id: 'bird',
      source: _rain.copyWith(id: 'bird'),
    ),
  ],
);

class _AudioPlayer implements LocalAudioPlayer {
  final completions = StreamController<bool>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final loaded = <String>[];
  bool isPlaying = false;
  Completer<void>? loadReady;
  Object? loadError;
  @override
  Stream<bool> get completedStream => completions.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration> get durationStream => durations.stream;
  @override
  Future<void> load(PlayableMedia media) async {
    await loadReady?.future;
    if (loadError != null) throw loadError!;
    loaded.add(media.locator);
  }

  @override
  Future<void> play() async => isPlaying = true;
  @override
  Future<void> pause() async => isPlaying = false;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async => isPlaying = false;

  void finishTrack() {
    isPlaying = false;
    completions.add(true);
  }

  @override
  void dispose() {
    isPlaying = false;
    unawaited(completions.close());
    unawaited(positions.close());
    unawaited(durations.close());
  }
}
