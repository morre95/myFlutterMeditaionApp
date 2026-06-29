import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/history/application/history_controller.dart';
import 'package:my_meditation_app/features/history/infrastructure/shared_preferences_session_repository.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/features/timer/application/timer_bell_player.dart';
import 'package:my_meditation_app/features/timer/application/timer_controller.dart';
import 'package:my_meditation_app/features/timer/application/wake_lock.dart';
import 'package:my_meditation_app/features/timer/domain/bell_selection.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('plays a built-in bell asset on completion', () {
    fakeAsync((async) {
      final bellPlayer = _FakeBellPlayer();
      final controller = TimerController(
        bellPlayer: bellPlayer,
        wakeLock: _FakeWakeLock(),
      );
      controller.setDuration(const Duration(minutes: 1));

      controller.start();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();

      expect(controller.state.status, TimerSessionStatus.completed);
      expect(bellPlayer.playedAsset, 'bells/bell_1.mp3');
      expect(bellPlayer.playedMedia, isNull);

      controller.dispose();
    });
  });

  test('resolves and plays a custom bell on completion', () {
    fakeAsync((async) {
      final bellPlayer = _FakeBellPlayer();
      final controller = TimerController(
        bellPlayer: bellPlayer,
        sourceResolver: const LocalPlaybackSourceResolver(),
        wakeLock: _FakeWakeLock(),
      );
      controller.setDuration(const Duration(minutes: 1));
      controller.setBell(
        const BellSelection.custom(
          AudioSource(
            id: 'local:/bells/gong.mp3',
            kind: AudioSourceKind.localFile,
            displayName: 'gong.mp3',
            reference: '/bells/gong.mp3',
          ),
        ),
      );

      controller.start();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();

      expect(bellPlayer.playedAsset, isNull);
      expect(bellPlayer.playedMedia?.kind, PlayableMediaKind.file);
      expect(bellPlayer.playedMedia?.locator, '/bells/gong.mp3');

      controller.dispose();
    });
  });

  test('previewBell plays the selected built-in bell immediately', () async {
    final bellPlayer = _FakeBellPlayer();
    final controller = TimerController(
      bellPlayer: bellPlayer,
      wakeLock: _FakeWakeLock(),
    );

    await controller.previewBell(const BellSelection.builtIn('bell_2'));

    expect(bellPlayer.playedAsset, 'bells/bell_2.mp3');
    expect(controller.state.status, TimerSessionStatus.idle);

    controller.dispose();
  });

  test('previewBell resolves and plays a custom bell', () async {
    final bellPlayer = _FakeBellPlayer();
    final controller = TimerController(
      bellPlayer: bellPlayer,
      sourceResolver: const LocalPlaybackSourceResolver(),
      wakeLock: _FakeWakeLock(),
    );

    await controller.previewBell(
      const BellSelection.custom(
        AudioSource(
          id: 'local:/bells/gong.mp3',
          kind: AudioSourceKind.localFile,
          displayName: 'gong.mp3',
          reference: '/bells/gong.mp3',
        ),
      ),
    );

    expect(bellPlayer.playedMedia?.kind, PlayableMediaKind.file);
    expect(bellPlayer.playedMedia?.locator, '/bells/gong.mp3');

    controller.dispose();
  });

  test('records a session in history on completion', () {
    SharedPreferences.setMockInitialValues({});
    fakeAsync((async) {
      final history = HistoryController(
        repository: SharedPreferencesSessionRepository(),
        clock: () => DateTime(2026, 6, 6, 9),
      );
      final controller = TimerController(
        bellPlayer: _FakeBellPlayer(),
        history: history,
        wakeLock: _FakeWakeLock(),
      );
      controller.setDuration(const Duration(minutes: 1));

      controller.start();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();

      expect(history.totalCount, 1);
      expect(history.currentStreak, 1);

      controller.dispose();
      history.dispose();
    });
  });

  test('acquires the wakelock when a session starts', () {
    final wakeLock = _FakeWakeLock();
    final controller = TimerController(
      bellPlayer: _FakeBellPlayer(),
      wakeLock: wakeLock,
    );

    controller.start();

    expect(wakeLock.isEnabled, isTrue);

    controller.dispose();
  });

  test('releases the wakelock when paused', () {
    final wakeLock = _FakeWakeLock();
    final controller = TimerController(
      bellPlayer: _FakeBellPlayer(),
      wakeLock: wakeLock,
    );

    controller.start();
    controller.pause();

    expect(wakeLock.isEnabled, isFalse);

    controller.dispose();
  });

  test('releases the wakelock when reset', () {
    final wakeLock = _FakeWakeLock();
    final controller = TimerController(
      bellPlayer: _FakeBellPlayer(),
      wakeLock: wakeLock,
    );

    controller.start();
    controller.reset();

    expect(wakeLock.isEnabled, isFalse);

    controller.dispose();
  });

  test('releases the wakelock on completion', () {
    fakeAsync((async) {
      final wakeLock = _FakeWakeLock();
      final controller = TimerController(
        bellPlayer: _FakeBellPlayer(),
        wakeLock: wakeLock,
      );
      controller.setDuration(const Duration(minutes: 1));

      controller.start();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();

      expect(controller.state.status, TimerSessionStatus.completed);
      expect(wakeLock.isEnabled, isFalse);

      controller.dispose();
    });
  });
}

class _FakeBellPlayer implements BellPlayer {
  String? playedAsset;
  PlayableMedia? playedMedia;

  @override
  Future<void> playAsset(String assetPath) async {
    playedAsset = assetPath;
  }

  @override
  Future<void> playMedia(PlayableMedia media) async {
    playedMedia = media;
  }

  @override
  void dispose() {}
}

class _FakeWakeLock implements WakeLock {
  bool isEnabled = false;

  @override
  Future<void> enable() async {
    isEnabled = true;
  }

  @override
  Future<void> disable() async {
    isEnabled = false;
  }
}
