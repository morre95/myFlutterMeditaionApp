import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:audio_service/audio_service.dart';
import 'package:my_meditation_app/features/meditation/application/meditation_audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/meditation/application/meditation_session_controller.dart';
import 'package:my_meditation_app/features/meditation/infrastructure/shared_preferences_meditation_settings_repository.dart';
import 'package:my_meditation_app/features/player/application/local_audio_playback_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_ownership_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/features/playlists/application/playlist_playback_controller.dart';
import 'package:my_meditation_app/features/playlists/domain/playlist.dart';
import 'package:my_meditation_app/features/settings/application/app_settings_controller.dart';
import 'package:my_meditation_app/features/settings/infrastructure/shared_preferences_app_settings_repository.dart';
import 'package:my_meditation_app/features/timer/application/bell_ringer.dart';
import 'package:my_meditation_app/features/timer/application/timer_bell_player.dart';
import 'package:my_meditation_app/features/timer/domain/bell_selection.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_meditation_app/features/history/application/history_controller.dart';
import 'package:my_meditation_app/features/history/domain/meditation_session.dart';
import 'package:my_meditation_app/features/history/infrastructure/shared_preferences_session_repository.dart';

const _gong = AudioSource(
  id: 'local:/bells/gong.mp3',
  kind: AudioSourceKind.localFile,
  displayName: 'gong.mp3',
  reference: '/bells/gong.mp3',
);

const _rain = AudioSource(
  id: 'import:rain',
  kind: AudioSourceKind.localFile,
  displayName: 'rain.wav',
  reference: '/sounds/rain/audio.wav',
  storedSize: 3,
);

class _Harness {
  _Harness(
    this.async, {
    PlaybackSourceResolver? resolver,
    ElapsedClock? clock,
    PlaybackSourceResolver? bellResolver,
    Future<bool> Function()? acquireAudioFocus,
  }) : audio = _AudioPlayer() {
    bellPlayer = _BellPlayer(audio.log);
    player = LocalAudioPlaybackController(player: audio, resolver: resolver);
    session = MeditationSessionController(
      player: player,
      bell: BellRinger(
        player: bellPlayer,
        sourceResolver: bellResolver ?? const LocalPlaybackSourceResolver(),
      ),
      repository: SharedPreferencesMeditationSettingsRepository(),
      ownership: ownership,
      appSettings: appSettings,
      clock: clock ?? () => async.elapsed,
      acquireAudioFocus: acquireAudioFocus,
      history: history,
    );
  }

  final history = HistoryController(
    repository: SharedPreferencesSessionRepository(),
  );
  final FakeAsync async;
  final _AudioPlayer audio;
  late final _BellPlayer bellPlayer;
  final ownership = PlaybackOwnershipController();
  final appSettings = AppSettingsController(
    repository: SharedPreferencesAppSettingsRepository(),
  );
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
    appSettings.dispose();
    async.flushMicrotasks();
  }
}

void main() {
  test(
    'streamed unknown-duration repeats and pause persist completed active progress',
    () {
      fakeAsync((async) {
        final h = _Harness(async, resolver: _StreamResolver());
        h.startWith(_cloud, const Duration(minutes: 1));
        async.elapse(const Duration(seconds: 3));
        h.audio.positions.add(const Duration(seconds: 10));
        async.flushMicrotasks();
        h.audio.completions.add(true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        h.audio.positions.add(const Duration(seconds: 20));
        async.flushMicrotasks();
        h.session.pause();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        h.session.resume();
        async.flushMicrotasks();
        h.audio.positions.add(const Duration(seconds: 50));
        async.flushMicrotasks();
        h.session.end();
        h.session.end();
        async.flushMicrotasks();
        expect(
          h.history.sessions.single.actualDuration,
          const Duration(minutes: 1),
        );
        expect(h.history.sessions.single.outcome, SessionOutcome.completed);
        expect(h.history.currentStreak, 1);
        h.dispose();
      });
    },
  );

  test('completed Meditate survives reentrant End and repeated completion', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final handler = MeditationAudioHandler(session: h.session);
      h.session.addListener(() {
        if (h.session.state.status == MeditationSessionStatus.completed) {
          h.session.end();
        }
      });
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 1));
      h.audio.completions.add(true);
      async.flushMicrotasks();
      expect(
        h.history.sessions.single.actualDuration,
        const Duration(minutes: 1),
      );
      expect(h.history.sessions.single.outcome, SessionOutcome.completed);
      expect(h.history.currentStreak, 1);
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.isSilencing, isFalse);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      handler.dispose();
      h.dispose();
    });
  });

  test('End records measured active time once across loading and pause', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.audio.loadReady = Completer<void>();
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 8));
      h.audio.loadReady!.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 7));
      h.session.pause();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
      h.session.resume();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      h.session.end();
      h.session.end();
      h.audio.completions.add(true);
      async.flushMicrotasks();
      expect(
        h.history.sessions.single.actualDuration,
        const Duration(seconds: 12),
      );
      expect(
        h.history.sessions.single.plannedDuration,
        const Duration(minutes: 1),
      );
      expect(h.history.sessions.single.outcome, SessionOutcome.endedEarly);
      expect(h.history.currentStreak, 0);
      h.dispose();
    });
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an interruption silences the ending bell without auto-resume', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final handler = MeditationAudioHandler(session: h.session);
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 1));
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      handler.handleInterruption(began: true);
      async.flushMicrotasks();
      handler.handleInterruption(began: false);
      async.flushMicrotasks();
      expect(h.audio.log.last, 'bell stop');
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.session.remaining, Duration.zero);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(h.audio.isPlaying, isFalse);
      handler.dispose();
      h.dispose();
    });
  });

  test(
    'background protection covers resolving and playing the ending bell',
    () {
      fakeAsync((async) {
        final resolver = _StreamResolver()
          ..pending = Completer<PlayableMedia>();
        final h = _Harness(async, bellResolver: resolver);
        final handler = MeditationAudioHandler(session: h.session);
        h.appSettings.addCustomBell(_cloud);
        h.session.selectBell(const BellSelection.custom(_cloud));
        h.startWith(_rain, const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 1));
        expect(h.session.state.status, MeditationSessionStatus.completed);
        expect(h.session.remaining, Duration.zero);
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.ready,
        );
        expect(
          handler.playbackState.value.controls.single.action,
          MediaAction.stop,
        );
        resolver.pending!.complete(
          const PlayableMedia.url('https://example.test/bell'),
        );
        async.flushMicrotasks();
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.ready,
        );
        h.bellPlayer.finish();
        async.flushMicrotasks();
        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
        handler.dispose();
        h.dispose();
      });
    },
  );

  test('failed End stays recoverable and blocks starting another session', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final handler = MeditationAudioHandler(session: h.session);
      h.startWith(_rain, const Duration(minutes: 1));
      h.audio.stopError = StateError('native Stop rejected');
      h.audio.pauseError = StateError('native Pause rejected');
      handler.stop();
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.paused);
      expect(h.session.state.errorMessage, isNotNull);
      expect(
        handler.playbackState.value.controls.single.action,
        MediaAction.stop,
      );
      h.session.start();
      handler.play();
      async.flushMicrotasks();
      expect(h.audio.loaded, hasLength(1));
      h.audio.stopError = null;
      h.audio.pauseError = null;
      handler.stop();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.state.status, MeditationSessionStatus.setup);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      handler.dispose();
      h.dispose();
    });
  });

  test('latest Resume wins while an earlier focus request is delayed', () {
    fakeAsync((async) {
      final requests = <Completer<bool>>[];
      final h = _Harness(
        async,
        acquireAudioFocus: () {
          final request = Completer<bool>();
          requests.add(request);
          return request.future;
        },
      );
      h.startWith(_rain, const Duration(minutes: 1));
      requests.first.complete(true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 7));
      h.session.pause();
      async.flushMicrotasks();
      h.session.resume();
      async.flushMicrotasks();
      h.session.pause();
      async.flushMicrotasks();
      h.session.resume();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 2));
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.remaining, const Duration(seconds: 53));
      requests.last.complete(true);
      async.flushMicrotasks();
      requests[1].complete(false);
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.running);
      expect(h.audio.isPlaying, isTrue);
      expect(h.audio.loaded, hasLength(2));
      h.dispose();
    });
  });

  test('denied focus holds time until explicit successful Resume', () {
    fakeAsync((async) {
      var granted = false;
      final h = _Harness(async, acquireAudioFocus: () async => granted);
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 2));
      expect(h.session.state.status, MeditationSessionStatus.paused);
      expect(h.session.state.errorMessage, isNotNull);
      expect(h.session.remaining, const Duration(minutes: 1));
      expect(h.audio.isPlaying, isFalse);
      granted = true;
      h.session.resume();
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.running);
      expect(h.audio.isPlaying, isTrue);
      h.dispose();
    });
  });

  testWidgets('stale End on a fresh launch is harmless', (tester) async {
    fakeAsync((async) {
      final h = _Harness(async);
      final handler = MeditationAudioHandler(session: h.session);
      handler.stop();
      handler.play();
      async.flushMicrotasks();
      expect(tester.takeException(), isNull);
      expect(handler.mediaItem.value, isNull);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      expect(h.audio.isPlaying, isFalse);
      handler.dispose();
      h.dispose();
    });
  });

  test('interruption silences local audio even when native Pause fails', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 9));
      h.audio.pauseError = StateError('native pause rejected');
      h.session.pause().catchError((Object _) {});
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.state.status, MeditationSessionStatus.paused);
      async.elapse(const Duration(minutes: 2));
      expect(h.session.remaining, const Duration(seconds: 51));
      h.dispose();
    });
  });

  test('End keeps background protection until native sound stops', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final handler = MeditationAudioHandler(session: h.session);
      h.startWith(_rain, const Duration(minutes: 1));
      h.audio.stopReady = Completer<void>();
      handler.stop();
      handler.play();
      async.flushMicrotasks();
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      h.audio.stopReady!.complete();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isFalse);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      handler.dispose();
      h.dispose();
    });
  });

  test('focus interruption and recovery require explicit Resume', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final handler = MeditationAudioHandler(session: h.session);
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 17));
      handler.handleInterruption(began: true);
      async.flushMicrotasks();
      handler.handleInterruption(began: false);
      async.elapse(const Duration(minutes: 3));
      expect(h.session.state.status, MeditationSessionStatus.paused);
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.remaining, const Duration(seconds: 43));
      handler.play();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isTrue);
      handler.dispose();
      h.dispose();
    });
  });

  test('End during focus acquisition never starts audio', () {
    fakeAsync((async) {
      final focus = Completer<bool>();
      final h = _Harness(async, acquireAudioFocus: () => focus.future);
      h.startWith(_rain, const Duration(minutes: 1));
      expect(h.audio.isPlaying, isFalse);
      h.session.end();
      async.flushMicrotasks();
      focus.complete(true);
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.setup);
      expect(h.audio.isPlaying, isFalse);
      h.dispose();
    });
  });

  test('an old notification cannot control the next session', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final handler = MeditationAudioHandler(session: h.session);
      h.startWith(_rain, const Duration(minutes: 1));
      final oldId = handler.mediaItem.value!.id;
      handler.stop();
      async.flushMicrotasks();
      h.session.start();
      async.flushMicrotasks();
      handler.customAction('end:$oldId', {'sessionId': oldId});
      handler.customAction('pause:$oldId', {'sessionId': oldId});
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.running);
      expect(h.audio.isPlaying, isTrue);
      final currentId = handler.mediaItem.value!.id;
      handler.customAction('pause:$currentId', {'sessionId': currentId});
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.paused);
      handler.dispose();
      h.dispose();
    });
  });

  test('background controls share the session and cannot resume after End', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final handler = MeditationAudioHandler(session: h.session);
      h.startWith(_rain, const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.mediaItem.value!.title, 'rain.wav');
      async.elapse(const Duration(seconds: 12));
      handler.pause();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isFalse);
      async.elapse(const Duration(minutes: 2));
      expect(h.session.remaining, const Duration(seconds: 48));
      handler.play();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isTrue);
      handler.stop();
      handler.play();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.state.status, MeditationSessionStatus.setup);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
      handler.dispose();
      h.dispose();
    });
  });

  test('interruption while loading requires explicit Resume', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.audio.loadReady = Completer<void>();
      h.startWith(_rain, const Duration(minutes: 1));
      h.session.pause();
      async.flushMicrotasks();
      h.audio.loadReady!.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 2));
      expect(h.session.state.status, MeditationSessionStatus.paused);
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.remaining, const Duration(minutes: 1));
      h.session.resume();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isTrue);
      h.dispose();
    });
  });

  test('stream loading and stalled positions consume no meditation time', () {
    fakeAsync((async) {
      final h = _Harness(async, resolver: _StreamResolver());
      h.startWith(_cloud, const Duration(minutes: 1));
      expect(h.session.state.status, MeditationSessionStatus.loading);
      async.elapse(const Duration(seconds: 2));
      expect(h.session.remaining, const Duration(minutes: 1));
      h.audio.positions.add(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.running);
      expect(h.session.remaining, const Duration(seconds: 58));
      async.elapse(const Duration(seconds: 10));
      expect(h.session.state.status, MeditationSessionStatus.paused);
      expect(h.session.remaining, const Duration(seconds: 58));
      expect(h.audio.isPlaying, isFalse);
      h.dispose();
    });
  });

  test('stream failure preserves progress and Resume seeks a fresh source', () {
    fakeAsync((async) {
      final resolver = _StreamResolver();
      final h = _Harness(async, resolver: resolver);
      h.startWith(_cloud, const Duration(minutes: 1));
      h.audio.positions.add(const Duration(seconds: 12));
      async.flushMicrotasks();
      h.audio.durations.addError(StateError('network failed'));
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.paused);
      expect(h.audio.isPlaying, isFalse);
      async.elapse(const Duration(minutes: 1));
      expect(h.session.remaining, const Duration(seconds: 48));
      h.session.resume();
      async.flushMicrotasks();
      expect(h.audio.loaded, [
        'https://stream.example/1',
        'https://stream.example/2',
      ]);
      expect(h.audio.seekPosition, const Duration(seconds: 12));
      expect(h.session.state.sound!.reference, '42');
      expect(h.session.remaining, const Duration(seconds: 48));
      h.audio.positions.add(const Duration(seconds: 14));
      async.flushMicrotasks();
      expect(h.session.remaining, const Duration(seconds: 46));
      h.dispose();
    });
  });

  test('stream retry finishing after End cannot replace a new session', () {
    fakeAsync((async) {
      final resolver = _StreamResolver();
      final h = _Harness(async, resolver: resolver);
      h.startWith(_cloud, const Duration(minutes: 1));
      h.audio.positions.add(const Duration(seconds: 7));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      resolver.pending = Completer<PlayableMedia>();
      h.session.resume();
      async.flushMicrotasks();
      h.session.resume();
      h.session.end();
      async.flushMicrotasks();
      h.startWith(_rain, const Duration(minutes: 2));
      resolver.pending!.complete(
        const PlayableMedia.url('https://expired.example/old'),
      );
      async.flushMicrotasks();
      expect(h.session.state.sound!.id, _rain.id);
      expect(h.session.remaining, const Duration(minutes: 2));
      expect(h.audio.loaded, ['https://stream.example/1', _rain.reference]);
      expect(h.audio.isPlaying, isTrue);
      h.dispose();
    });
  });

  test('stream repeats without counting an unplayed declared tail', () {
    fakeAsync((async) {
      final h = _Harness(async, resolver: _StreamResolver());
      h.startWith(_cloud, const Duration(minutes: 1));
      h.audio.durations.add(const Duration(seconds: 40));
      h.audio.positions.add(const Duration(seconds: 10));
      async.flushMicrotasks();
      h.audio.finishTrack();
      async.flushMicrotasks();
      expect(h.session.remaining, const Duration(seconds: 50));
      expect(h.session.state.status, MeditationSessionStatus.loading);
      h.audio.positions.add(const Duration(seconds: 50));
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.audio.isPlaying, isFalse);
      h.dispose();
    });
  });

  test('End during volume preparation cannot start a stale stream', () {
    fakeAsync((async) {
      final h = _Harness(async, resolver: _StreamResolver());
      h.audio.volumeReady = Completer<void>();
      h.startWith(_cloud, const Duration(minutes: 1));
      h.session.end();
      h.audio.volumeReady!.complete();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isFalse);
      expect(h.audio.loaded, isEmpty);
      expect(h.session.state.status, MeditationSessionStatus.setup);
      h.dispose();
    });
  });

  test('a failed native Pause silences the stream and keeps progress', () {
    fakeAsync((async) {
      final h = _Harness(async, resolver: _StreamResolver());
      h.startWith(_cloud, const Duration(minutes: 1));
      h.audio.positions.add(const Duration(seconds: 9));
      async.flushMicrotasks();
      h.audio.pauseError = StateError('pause rejected');
      h.session.pause();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isFalse);
      expect(h.session.state.status, MeditationSessionStatus.paused);
      expect(h.session.remaining, const Duration(seconds: 51));
      expect(h.session.state.errorMessage, isNotNull);
      h.dispose();
    });
  });

  test(
    'Resume waits for pending native Pause before counting stream positions',
    () {
      fakeAsync((async) {
        final h = _Harness(async, resolver: _StreamResolver());
        h.startWith(_cloud, const Duration(minutes: 1));
        h.audio.positions.add(const Duration(seconds: 9));
        async.flushMicrotasks();
        h.audio.pauseReady = Completer<void>();
        h.session.pause();
        async.flushMicrotasks();
        h.session.resume();
        h.audio.positions.add(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.loading);
        expect(h.session.remaining, const Duration(seconds: 51));
        h.audio.pauseReady!.complete();
        async.flushMicrotasks();
        expect(h.audio.seekPosition, const Duration(seconds: 9));
        expect(h.audio.isPlaying, isTrue);
        h.audio.positions.add(const Duration(seconds: 11));
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.running);
        expect(h.session.remaining, const Duration(seconds: 49));
        h.dispose();
      });
    },
  );

  test(
    'a rejected recovery Stop falls back to Pause and explicit Resume continues',
    () {
      fakeAsync((async) {
        final h = _Harness(async, resolver: _StreamResolver());
        h.startWith(_cloud, const Duration(minutes: 1));
        h.audio.positions.add(const Duration(seconds: 9));
        async.flushMicrotasks();
        h.audio.stopError = StateError('stop rejected');
        h.audio.durations.addError(StateError('stream failed'));
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.paused);
        expect(h.audio.isPlaying, isFalse);
        expect(h.session.remaining, const Duration(seconds: 51));
        h.session.resume();
        async.flushMicrotasks();
        h.audio.positions.add(const Duration(seconds: 11));
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.running);
        expect(h.session.remaining, const Duration(seconds: 49));
        h.audio.stopError = null;
        h.dispose();
      });
    },
  );

  test(
    'failed Stop and Pause show inability to silence without stranding Resume',
    () {
      fakeAsync((async) {
        final h = _Harness(async, resolver: _StreamResolver());
        h.startWith(_cloud, const Duration(minutes: 1));
        h.audio.positions.add(const Duration(seconds: 9));
        async.flushMicrotasks();
        h.audio.stopReady = Completer<void>();
        h.audio.stopError = StateError('stop rejected');
        h.audio.pauseError = StateError('pause rejected');
        async.elapse(const Duration(seconds: 5));
        h.session.resume();
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.loading);
        h.audio.stopReady!.complete();
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.paused);
        expect(
          h.session.state.errorMessage,
          'Could not silence the sound. Resume to try again.',
        );
        expect(h.session.remaining, const Duration(seconds: 51));
        h.audio.stopError = null;
        h.audio.pauseError = null;
        h.session.resume();
        async.flushMicrotasks();
        h.audio.positions.add(const Duration(seconds: 11));
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.running);
        expect(h.session.remaining, const Duration(seconds: 49));
        h.dispose();
      });
    },
  );

  test(
    'resolver failures on Start and retry pause until explicit fresh recovery',
    () {
      fakeAsync((async) {
        final resolver = _StreamResolver()
          ..pending = Completer<PlayableMedia>();
        final h = _Harness(async, resolver: resolver);
        h.startWith(_cloud, const Duration(minutes: 1));
        async.elapse(const Duration(seconds: 30));
        expect(h.session.state.status, MeditationSessionStatus.loading);
        expect(h.session.remaining, const Duration(minutes: 1));
        resolver.pending!.completeError(StateError('expired authentication'));
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.paused);
        expect(h.session.state.errorMessage, 'Could not play Cloud rain.');
        expect(h.audio.isPlaying, isFalse);
        resolver.pending = null;
        h.session.resume();
        async.flushMicrotasks();
        h.audio.positions.add(const Duration(seconds: 6));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(h.session.remaining, const Duration(seconds: 54));
        resolver.pending = Completer<PlayableMedia>();
        h.session.resume();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(h.session.state.status, MeditationSessionStatus.loading);
        expect(h.session.remaining, const Duration(seconds: 54));
        resolver.pending!.completeError(StateError('network unavailable'));
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.paused);
        expect(h.session.remaining, const Duration(seconds: 54));
        expect(h.audio.isPlaying, isFalse);
        resolver.pending = null;
        h.session.resume();
        async.flushMicrotasks();
        expect(h.audio.loaded, [
          'https://stream.example/1',
          'https://stream.example/2',
        ]);
        expect(h.audio.seekPosition, const Duration(seconds: 6));
        h.audio.positions.add(const Duration(seconds: 8));
        async.flushMicrotasks();
        expect(h.session.state.status, MeditationSessionStatus.running);
        expect(h.session.remaining, const Duration(seconds: 52));
        h.dispose();
      });
    },
  );

  test('late failed resolution after End cannot interrupt a new session', () {
    fakeAsync((async) {
      final resolver = _StreamResolver()..pending = Completer<PlayableMedia>();
      final h = _Harness(async, resolver: resolver);
      h.startWith(_cloud, const Duration(minutes: 1));
      h.session.end();
      async.flushMicrotasks();
      h.startWith(_rain, const Duration(minutes: 2));
      resolver.pending!.completeError(StateError('obsolete cloud failure'));
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.running);
      expect(h.session.state.errorMessage, isNull);
      expect(h.session.state.sound!.id, _rain.id);
      expect(h.session.remaining, const Duration(minutes: 2));
      expect(h.audio.loaded, [_rain.reference]);
      expect(h.audio.isPlaying, isTrue);
      h.dispose();
    });
  });

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

  test('Resume before the native pause settles keeps the position', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 10));
      async.elapse(const Duration(minutes: 4));
      h.audio.pauseReady = Completer<void>();
      h.session.pause();
      async.flushMicrotasks();
      h.session.resume();
      h.audio.positions.add(const Duration(minutes: 4));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      h.audio.pauseReady!.complete();
      async.flushMicrotasks();
      expect(h.audio.loaded, hasLength(1));
      expect(h.audio.isPlaying, isTrue);
      expect(h.session.state.status, MeditationSessionStatus.running);
      async.elapse(const Duration(minutes: 1));
      expect(h.session.remaining, const Duration(minutes: 5));
      h.dispose();
    });
  });

  test('a near-zero-length sound ends the session instead of reloading', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 10));
      async.elapse(const Duration(milliseconds: 200));
      h.audio.finishTrack();
      async.flushMicrotasks();
      expect(h.audio.loaded, hasLength(1));
      expect(h.session.state.status, MeditationSessionStatus.setup);
      expect(h.session.state.errorMessage, 'rain.wav is too short to repeat.');
      h.dispose();
    });
  });

  test('a play-through split by Pause still repeats normally', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 10));
      async.elapse(const Duration(minutes: 1));
      h.session.pause();
      async.flushMicrotasks();
      h.session.resume();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 200));
      h.audio.finishTrack();
      async.flushMicrotasks();
      expect(h.audio.loaded, hasLength(2));
      expect(h.session.state.status, MeditationSessionStatus.running);
      h.dispose();
    });
  });

  test('the sound fades over the final five active seconds, then stops', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.session.setBellEnabled(false);
      h.startWith(_rain, const Duration(minutes: 1));
      expect(h.audio.volume, 1);
      async.elapse(const Duration(seconds: 55));
      expect(h.audio.volume, 1);

      async.elapse(const Duration(milliseconds: 2500));
      expect(h.audio.volume, closeTo(0.5, 0.001));
      expect(h.audio.isPlaying, isTrue);

      async.elapse(const Duration(milliseconds: 2500));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.audio.log.last, 'stop');
      final lastVolume = h.audio.log[h.audio.log.length - 2];
      expect(lastVolume, 'volume 0.02');
      h.dispose();
    });
  });

  test('pausing during the fade holds volume and remaining time', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 57));
      h.session.pause();
      async.flushMicrotasks();
      async.elapse(const Duration(hours: 1));
      expect(h.session.state.status, MeditationSessionStatus.paused);
      expect(h.session.remaining, const Duration(seconds: 3));
      expect(h.audio.volume, closeTo(0.6, 0.001));

      h.session.resume();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1500));
      expect(h.audio.volume, closeTo(0.3, 0.001));
      async.elapse(const Duration(minutes: 1));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.audio.log.where((entry) => entry == 'stop'), hasLength(1));
      h.dispose();
    });
  });

  test('the next session starts at full volume after a faded one', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 1));
      h.session.end();
      async.flushMicrotasks();

      h.session.start();
      async.flushMicrotasks();
      expect(h.audio.isPlaying, isTrue);
      expect(h.audio.volume, 1);
      h.dispose();
    });
  });

  test('the chosen bell rings once the faded sound has stopped', () {
    fakeAsync((async) {
      final h = _Harness(async);
      expect(h.session.state.isBellEnabled, isTrue);
      h.session.selectBell(const BellSelection.builtIn('bell_3'));
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 1));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.audio.log.sublist(h.audio.log.length - 3), [
        'volume 0.02',
        'stop',
        'bell bells/bell_3.mp3',
      ]);
      h.dispose();
    });
  });

  test('a disabled bell leaves completion silent', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.session.setBellEnabled(false);
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 2));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(
        h.audio.log.where((entry) => entry.startsWith('bell bells/')),
        isEmpty,
      );
      h.dispose();
    });
  });

  test('a session resumed during the fade rings its bell once', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 57));
      h.session.pause();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      h.session.resume();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.audio.log.where((entry) => entry.startsWith('bell bells/')), [
        'bell bells/bell_1.mp3',
      ]);
      h.dispose();
    });
  });

  test('a failed bell keeps the session complete and the sound stopped', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.bellPlayer.error = StateError('native bell failed');
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 2));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.session.state.errorMessage, 'Could not play bell_1.');
      expect(h.audio.loaded, hasLength(1));
      expect(h.audio.isPlaying, isFalse);

      h.session.end();
      async.flushMicrotasks();
      expect(h.session.state.status, MeditationSessionStatus.setup);
      expect(h.session.state.errorMessage, isNull);
      h.dispose();
    });
  });

  test('Music taking over silences a ringing bell', () {
    fakeAsync((async) {
      final h = _Harness(async);
      final musicAudio = _AudioPlayer();
      final musicPlayer = LocalAudioPlaybackController(player: musicAudio);
      final music = PlaylistPlaybackController(
        player: musicPlayer,
        ownership: h.ownership,
      );
      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 1));
      expect(h.audio.log.last, 'bell bells/bell_1.mp3');

      music.playPlaylist(_playlist());
      async.flushMicrotasks();
      expect(h.audio.log.last, 'bell stop');
      expect(musicAudio.isPlaying, isTrue);

      music.dispose();
      musicPlayer.dispose();
      h.dispose();
    });
  });

  test('bell and enabled setting are locked once a session starts', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 1));
      h.session.selectBell(const BellSelection.builtIn('bell_4'));
      h.session.setBellEnabled(false);
      async.elapse(const Duration(minutes: 1));
      expect(h.audio.log.last, 'bell bells/bell_1.mp3');
      h.dispose();
    });
  });

  test('sound, duration, bell, and bell setting are remembered', () {
    fakeAsync((async) {
      final first = _Harness(async);
      first.session.selectSound(_rain);
      first.session.setDuration(const Duration(minutes: 7));
      first.session.selectBell(const BellSelection.builtIn('bell_2'));
      first.session.setBellEnabled(false);
      async.flushMicrotasks();
      first.dispose();

      final next = _Harness(async);
      next.session.load();
      async.flushMicrotasks();
      final state = next.session.state;
      expect(state.sound!.id, _rain.id);
      expect(state.sound!.displayName, 'rain.wav');
      expect(state.duration, const Duration(minutes: 7));
      expect(state.bell.name, 'bell_2');
      expect(state.isBellEnabled, isFalse);
      next.dispose();
    });
  });

  test('a custom bell choice is remembered', () {
    fakeAsync((async) {
      final first = _Harness(async);
      first.session.selectBell(const BellSelection.custom(_gong));
      async.flushMicrotasks();
      first.dispose();

      final next = _Harness(async);
      next.session.load();
      async.flushMicrotasks();
      expect(next.session.state.bell.source!.id, _gong.id);
      expect(next.session.state.sound, isNull);
      expect(next.session.state.duration, const Duration(minutes: 20));
      next.dispose();
    });
  });

  test('a removed custom bell rings the bell setup falls back to', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.appSettings.addCustomBell(_gong);
      async.flushMicrotasks();
      h.session.selectBell(const BellSelection.custom(_gong));
      h.appSettings.removeCustomBell(_gong.id);
      async.flushMicrotasks();
      expect(h.session.bell.name, 'bell_1');

      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 1));
      expect(h.session.state.errorMessage, isNull);
      expect(h.audio.log.last, 'bell bells/bell_1.mp3');
      h.dispose();
    });
  });

  test('a disabled built-in bell rings the first enabled bell instead', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.session.selectBell(const BellSelection.builtIn('bell_1'));
      h.appSettings.disableBuiltInBell('bell_1');
      async.flushMicrotasks();
      expect(h.session.bell.name, 'bell_2');

      h.startWith(_rain, const Duration(minutes: 1));
      async.elapse(const Duration(minutes: 1));
      expect(h.audio.log.last, 'bell bells/bell_2.mp3');
      h.dispose();
    });
  });

  test('a failed volume reset returns to setup with an error', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.audio.volumeError = StateError('native volume failed');
      h.startWith(_rain, const Duration(minutes: 1));
      expect(h.session.state.status, MeditationSessionStatus.setup);
      expect(h.session.state.errorMessage, 'Could not play rain.wav.');
      expect(h.audio.isPlaying, isFalse);
      h.dispose();
    });
  });

  test('a failed fade step keeps the session running to its end', () {
    fakeAsync((async) {
      final h = _Harness(async);
      h.startWith(_rain, const Duration(minutes: 1));
      h.audio.volumeError = StateError('native volume failed');
      async.elapse(const Duration(minutes: 1));
      expect(h.session.state.status, MeditationSessionStatus.completed);
      expect(h.audio.log.last, 'bell bells/bell_1.mp3');
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

/// Records into the session player's log so ordering is observable.
class _BellPlayer implements BellPlayer, BellPlaybackLifecycle {
  @override
  Future<void> get playbackFinished => finished.future;
  var finished = Completer<void>();
  void finish() => finished.complete();
  _BellPlayer(this.log);

  final List<String> log;
  Object? error;

  @override
  Future<void> playAsset(String assetPath) async {
    if (error != null) throw error!;
    finished = Completer<void>();
    log.add('bell $assetPath');
  }

  @override
  Future<void> playMedia(PlayableMedia media) async {
    if (error != null) throw error!;
    finished = Completer<void>();
    log.add('bell ${media.locator}');
  }

  @override
  Future<void> stop() async {
    log.add('bell stop');
    if (!finished.isCompleted) finished.complete();
  }

  @override
  void dispose() {}
}

class _AudioPlayer implements LocalAudioPlayer {
  final completions = StreamController<bool>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final loaded = <String>[];
  bool isPlaying = false;
  double volume = 0.2;

  /// Volume changes and stops, in order.
  final log = <String>[];
  Completer<void>? loadReady;
  Completer<void>? pauseReady;
  Completer<void>? volumeReady;
  Completer<void>? stopReady;
  Object? loadError;
  Object? pauseError;
  Object? stopError;
  Object? volumeError;
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
  Future<void> pause() async {
    await pauseReady?.future;
    if (pauseError != null) throw pauseError!;
    isPlaying = false;
  }

  Duration? seekPosition;
  @override
  Future<void> seek(Duration position) async {
    seekPosition = position;
  }

  @override
  Future<void> stop() async {
    if (stopReady != null) await stopReady!.future;
    if (stopError != null) throw stopError!;
    isPlaying = false;
    log.add('stop');
  }

  @override
  Future<void> setVolume(double volume) async {
    await volumeReady?.future;
    if (volumeError != null) throw volumeError!;
    this.volume = volume;
    log.add('volume ${volume.toStringAsFixed(2)}');
  }

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

const _cloud = AudioSource(
  id: 'pcloud:42',
  kind: AudioSourceKind.pCloud,
  displayName: 'Cloud rain',
  reference: '42',
);

class _StreamResolver implements PlaybackSourceResolver {
  int links = 0;
  Completer<PlayableMedia>? pending;
  @override
  Future<PlayableMedia> resolve(AudioSource source) async =>
      source.kind == AudioSourceKind.localFile
      ? PlayableMedia.file(source.reference)
      : pending != null
      ? pending!.future
      : PlayableMedia.url('https://stream.example/${++links}');
}
