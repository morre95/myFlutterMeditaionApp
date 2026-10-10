import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/app/app_dependencies.dart';
import 'package:my_meditation_app/app/app_scope.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_session_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';
import 'package:my_meditation_app/features/home/presentation/home_screen.dart';
import 'package:my_meditation_app/features/library/application/local_audio_library.dart';
import 'package:my_meditation_app/features/meditation/domain/meditation_settings.dart';
import 'package:my_meditation_app/features/meditation/infrastructure/shared_preferences_meditation_settings_repository.dart';
import 'package:my_meditation_app/features/player/application/local_audio_playback_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/features/timer/application/timer_bell_player.dart';
import 'package:my_meditation_app/features/timer/domain/bell_selection.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real library files, a fake native player, and a hand-driven clock.
class _App {
  _App._(this.root, this.library, this.sound);

  static Future<_App> create({bool withSound = true}) async {
    final root = await Directory.systemTemp.createTemp('meditate-');
    final library = LocalAudioLibrary(
      directory: Directory('${root.path}/library'),
    );
    AudioSource? sound;
    if (withSound) {
      final original = await File('${root.path}/rain.wav').writeAsBytes([1]);
      sound = (await library.importSources([
        AudioSource(
          id: 'original',
          kind: AudioSourceKind.localFile,
          displayName: 'rain.wav',
          reference: original.path,
        ),
      ])).single;
    }
    return _App._(root, library, sound);
  }

  final Directory root;
  final LocalAudioLibrary library;
  final AudioSource? sound;
  var audio = _FakeLocalAudioPlayer();
  var now = Duration.zero;
  late AppDependencies deps = _launch();

  AppDependencies _launch() => AppDependencies(
    localAudioLibrary: library,
    meditationPlaybackController: LocalAudioPlaybackController(player: audio),
    meditationBellPlayer: _SilentBellPlayer(),
    pcloudDownloadStore: PCloudDownloadStore(
      directory: Directory('${root.path}/pcloud_downloads'),
    ),
    clock: () => now,
    pcloudAuthController: PCloudAuthController(store: _StubSessionStore()),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      AppScope(
        dependencies: deps,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.tap(find.text('Meditate'));
    // The sound list spins until real I/O finishes, so frames never settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  /// Closes the app and starts it again on the same storage.
  Future<void> relaunch(WidgetTester tester) async {
    await _close(tester);
    audio = _FakeLocalAudioPlayer();
    deps = _launch();
    await deps.init();
    await open(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await _close(tester);
    await root.delete(recursive: true);
  }

  Future<void> _close(WidgetTester tester) async {
    // Setup re-reads the library whenever it appears; let that read finish.
    await _pumpUntil(
      tester,
      find.byKey(const Key('meditate-sounds-loading')),
      expected: findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    deps.dispose();
  }
}

/// Polls frames while real file I/O inside `runAsync` completes.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Matcher expected = findsWidgets,
}) async {
  for (var i = 0; i < 200 && !expected.matches(finder, {}); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await tester.pump();
  }
  expect(finder, expected);
}

Future<void> _chooseSound(WidgetTester tester, String name) async {
  await _pumpUntil(tester, find.byKey(const Key('meditate-sound-dropdown')));
  await tester.tap(find.byKey(const Key('meditate-sound-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('setup offers imported sounds, 20 minutes, and a 1-120 range', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');

      final slider = tester.widget<Slider>(
        find.byKey(const Key('meditate-duration-slider')),
      );
      expect([slider.min, slider.max, slider.value], [1, 120, 20]);
      expect(find.text('20 minutes'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  testWidgets('an empty library explains how to add a sound', (tester) async {
    await tester.runAsync(() async {
      final app = await _App.create(withSound: false);
      await app.open(tester);
      await _pumpUntil(
        tester,
        find.text('Import a sound in Library to meditate with it.'),
      );
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(start.onPressed, isNull);
      await app.dispose(tester);
    });
  });

  testWidgets('Start, Pause, Resume, and End drive the active session', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');
      await tester.tap(find.text('Start'));
      await _pumpUntil(tester, find.text('Pause'));
      expect(find.text('20:00'), findsOneWidget);
      expect(app.audio.loadedPath, app.sound!.reference);
      expect(app.audio.isPlaying, isTrue);

      app.now += const Duration(minutes: 1);
      await tester.tap(find.text('Pause'));
      await _pumpUntil(tester, find.text('Resume'));
      expect(find.text('19:00'), findsOneWidget);
      expect(app.audio.isPlaying, isFalse);

      app.now += const Duration(minutes: 10);
      await tester.tap(find.text('Resume'));
      await _pumpUntil(tester, find.text('Pause'));
      expect(find.text('19:00'), findsOneWidget);
      expect(app.audio.isPlaying, isTrue);

      await tester.tap(find.text('End'));
      await _pumpUntil(tester, find.text('Start'));
      expect(app.audio.isPlaying, isFalse);
      await app.dispose(tester);
    });
  });

  testWidgets('leaving and returning to Meditate keeps the session', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');
      await tester.tap(find.text('Start'));
      await _pumpUntil(tester, find.text('Pause'));

      await tester.pageBack();
      await tester.pumpAndSettle();
      app.now += const Duration(minutes: 2);
      expect(app.audio.isPlaying, isTrue);
      await tester.tap(find.text('Meditate'));
      await tester.pumpAndSettle();
      expect(find.text('18:00'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(app.audio.loadCount, 1);
      await app.dispose(tester);
    });
  });

  testWidgets('a sound removed after selection shows an error, not a session', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');
      await File(app.sound!.reference).delete();
      await tester.tap(find.text('Start'));
      await _pumpUntil(tester, find.text('Could not play rain.wav.'));
      expect(find.text('Pause'), findsNothing);
      expect(app.audio.isPlaying, isFalse);
      await app.dispose(tester);
    });
  });

  testWidgets('the ending bell can be switched off', (tester) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');
      DropdownButtonFormField<String> bellPicker() =>
          tester.widget(find.byType(DropdownButtonFormField<String>).last);
      expect(find.text('Bell 1'), findsOneWidget);
      expect(bellPicker().onChanged, isNotNull);

      await tester.tap(find.byKey(const Key('meditate-bell-switch')));
      await tester.pump();
      expect(bellPicker().onChanged, isNull);
      expect(app.deps.meditationSessionController.state.isBellEnabled, isFalse);
      await app.dispose(tester);
    });
  });

  testWidgets('a relaunch restores the last sound and bell setting', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');
      await tester.tap(find.byKey(const Key('meditate-bell-switch')));
      await tester.pump();

      await app.relaunch(tester);
      await _pumpUntil(tester, find.text('rain.wav'));
      final bellSwitch = tester.widget<SwitchListTile>(
        find.byKey(const Key('meditate-bell-switch')),
      );
      expect(bellSwitch.value, isFalse);
      await tester.tap(find.text('Start'));
      await _pumpUntil(tester, find.text('Pause'));
      expect(app.audio.loadedPath, app.sound!.reference);
      await app.dispose(tester);
    });
  });

  testWidgets('a remembered sound that is gone explains why Start is off', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');
      await File(app.sound!.reference).parent.delete(recursive: true);

      await app.relaunch(tester);
      await _pumpUntil(
        tester,
        find.text('rain.wav is no longer available. Choose another sound.'),
      );
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(start.onPressed, isNull);
      await app.dispose(tester);
    });
  });

  testWidgets('Start plays the library copy of a remembered sound', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await SharedPreferencesMeditationSettingsRepository().save(
        MeditationSettings(
          sound: app.sound!.copyWith(reference: '/moved/audio.wav'),
          duration: const Duration(minutes: 20),
          bell: const BellSelection.builtIn('bell_1'),
          isBellEnabled: true,
        ),
      );

      await app.relaunch(tester);
      await _pumpUntil(tester, find.text('rain.wav'));
      await tester.tap(find.text('Start'));
      await _pumpUntil(tester, find.text('Pause'));
      expect(app.audio.loadedPath, app.sound!.reference);
      await app.dispose(tester);
    });
  });
}

class _SilentBellPlayer implements BellPlayer {
  @override
  Future<void> playAsset(String assetPath) async {}
  @override
  Future<void> playMedia(PlayableMedia media) async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

class _StubSessionStore implements PCloudSessionStore {
  @override
  Future<PCloudSession?> read() async => null;
  @override
  Future<void> write(PCloudSession session) async {}
  @override
  Future<void> clear() async {}
}

/// Mirrors the native player: loading a missing file fails.
class _FakeLocalAudioPlayer implements LocalAudioPlayer {
  final _completed = StreamController<bool>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  String? loadedPath;
  int loadCount = 0;
  bool isPlaying = false;

  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration> get durationStream => _durations.stream;

  @override
  Future<void> load(PlayableMedia media) async {
    if (!File(media.locator).existsSync()) {
      throw FileSystemException('missing', media.locator);
    }
    loadCount++;
    loadedPath = media.locator;
  }

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
    isPlaying = false;
    unawaited(_completed.close());
    unawaited(_positions.close());
    unawaited(_durations.close());
  }

  @override
  Future<void> setVolume(double volume) async {}
}
