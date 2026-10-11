import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_service.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_playback_source_resolver.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/app/app_dependencies.dart';
import 'package:my_meditation_app/app/app_scope.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_controller.dart';
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

  /// Requests to pCloud; the network is unreachable in these tests.
  var cloudRequests = 0;
  late AppDependencies deps = _launch();

  /// Saves a downloaded pCloud copy, as a finished download would.
  Future<AudioSource> download(String name) async {
    final source = AudioSource(
      id: 'pcloud:7',
      kind: AudioSourceKind.pCloud,
      displayName: name,
      reference: '7',
    );
    await PCloudDownloadStore(
      directory: Directory('${root.path}/pcloud_downloads'),
    ).save(source, Stream.value([1, 2]));
    return source;
  }

  AppDependencies _launch() {
    final auth = PCloudAuthController(store: _StubSessionStore());
    return AppDependencies(
      localAudioLibrary: library,
      pcloudAuthController: auth,
      pcloudService: PCloudService(
        session: auth,
        client: MockClient((_) async {
          cloudRequests++;
          throw http.ClientException('Network is unreachable');
        }),
      ),
      meditationPlaybackController: LocalAudioPlaybackController(
        player: audio,
        // The app's resolver exists only once the dependencies do.
        resolver: _AppResolver(() => deps.playbackSourceResolver),
      ),
      meditationBellPlayer: _SilentBellPlayer(),
      pcloudDownloadStore: PCloudDownloadStore(
        directory: Directory('${root.path}/pcloud_downloads'),
      ),
      clock: () => now,
    );
  }

  Future<void> open(WidgetTester tester) async {
    await _showHome(tester);
    await tester.tap(find.text('Meditate'));
    // The sound list spins until real I/O finishes, so frames never settle.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> _showHome(WidgetTester tester) => tester.pumpWidget(
    AppScope(
      dependencies: deps,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );

  /// Terminates the process without End and starts again on Home.
  Future<void> kill(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    deps.meditationSessionController.dispose();
    audio = _FakeLocalAudioPlayer();
    deps = _launch();
    await deps.init();
    await _showHome(tester);
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

  testWidgets('select a pCloud sound and recover with visible Resume', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      final auth = PCloudAuthController(store: _ConnectedStore());
      await auth.loadStoredSession();
      final service = PCloudService(
        session: auth,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(
              request.url.path.contains('listfolder')
                  ? {
                      'result': 0,
                      'metadata': {
                        'contents': [
                          {'name': 'cloud.wav', 'fileid': 42},
                        ],
                      },
                    }
                  : {
                      'result': 0,
                      'hosts': ['stream.example'],
                      'path': '/rain',
                    },
            ),
            200,
          );
        }),
      );
      app.deps = AppDependencies(
        localAudioLibrary: app.library,
        pcloudAuthController: auth,
        pcloudService: service,
        meditationPlaybackController: LocalAudioPlaybackController(
          player: app.audio,
          resolver: PCloudPlaybackSourceResolver(
            service: service,
            downloads: PCloudDownloadController(
              service: service,
              store: PCloudDownloadStore(
                directory: Directory('${app.root.path}/pcloud_downloads'),
              ),
            ),
            isOffline: () => false,
          ),
        ),
        meditationBellPlayer: _SilentBellPlayer(),
        clock: () => app.now,
      );
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');
      await tester.tap(find.text('Choose from pCloud'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select sound'));
      await tester.pump();
      await _pumpUntil(
        tester,
        find.byKey(const Key('meditate-sounds-loading')),
        expected: findsNothing,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('cloud.wav'), findsOneWidget);
      expect(find.text('rain.wav'), findsNothing);
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.text('Preparing sound…'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      app.audio._positions.add(const Duration(seconds: 8));
      await tester.pump();
      app.audio._durations.addError(StateError('offline'));
      await tester.pump();
      await _pumpUntil(tester, find.text('Resume'));
      expect(app.audio.isPlaying, isFalse);
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(find.text('Preparing sound…'), findsOneWidget);
      await tester.tap(find.text('End'));
      await tester.pump();
      await app.dispose(tester);
    });
  });

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
        find.text(
          'No audio files available to play. Import a sound in Library.',
        ),
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

  testWidgets('a terminated session relaunches paused until Resume or End', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');
      await tester.tap(find.text('Start'));
      await _pumpUntil(tester, find.text('Pause'));
      app.now += const Duration(minutes: 1);
      await tester.tap(find.text('Pause'));
      await _pumpUntil(tester, find.text('Resume'));

      await app.kill(tester);
      await _pumpUntil(tester, find.text('Resume'));
      expect(find.text('19:00'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(app.audio.loadCount, 0);
      expect(app.audio.isPlaying, isFalse);

      await tester.tap(find.text('Resume'));
      await _pumpUntil(tester, find.text('Pause'));
      expect(app.audio.loadedPath, app.sound!.reference);
      expect(find.text('19:00'), findsOneWidget);
      await tester.tap(find.text('End'));
      await _pumpUntil(tester, find.text('Start'));
      final recorded = app.deps.historyController.sessions.single;
      expect(recorded.actualDuration, const Duration(minutes: 1));
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

  testWidgets('Device storage keeps the sound of an active session', (
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
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device storage'));
      await _pumpUntil(tester, find.byTooltip('Remove rain.wav'));
      // Taps during the route transition land off-screen.
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove rain.wav'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await _pumpUntil(
        tester,
        find.text(
          'rain.wav is playing in an active session. '
          'End the session before removing it.',
        ),
      );

      expect(File(app.sound!.reference).existsSync(), isTrue);
      expect(app.audio.isPlaying, isTrue);
      await app.deps.meditationSessionController.end();
      await tester.pumpWidget(const SizedBox.shrink());
      app.deps.dispose();
      await app.root.delete(recursive: true);
    });
  });

  testWidgets('Offline mode plays device copies and hides pCloud browsing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.download('ocean.mp3');
      await app.deps.init();
      await app.deps.appSettingsController.setOfflineMode(true);
      await app.open(tester);

      expect(find.text('Choose from pCloud'), findsNothing);
      await _chooseSound(tester, 'ocean.mp3');
      await tester.tap(find.text('Start'));
      await _pumpUntil(tester, find.text('Pause'));
      // Verifying the copy on disk is real I/O.
      for (var i = 0; i < 200 && app.audio.loadedPath == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(app.audio.loadedPath, endsWith('pcloud_downloads/7/audio.mp3'));
      expect(app.cloudRequests, 0);
      await app.deps.meditationSessionController.end();
      await app.dispose(tester);
    });
  });

  testWidgets('Offline mode cannot start a pCloud sound without a copy', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await SharedPreferencesMeditationSettingsRepository().save(
        const MeditationSettings(
          sound: AudioSource(
            id: 'pcloud:9',
            kind: AudioSourceKind.pCloud,
            displayName: 'forest.mp3',
            reference: '9',
          ),
          duration: Duration(minutes: 20),
          bell: BellSelection.builtIn('bell_1'),
          isBellEnabled: true,
        ),
      );
      await app.deps.init();
      await app.deps.appSettingsController.setOfflineMode(true);
      await app.open(tester);

      await _pumpUntil(
        tester,
        find.text('forest.mp3 is not available offline. Choose another sound.'),
      );
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(start.onPressed, isNull);
      expect(app.cloudRequests, 0);
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

  testWidgets('an empty library hides the missing remembered sound error', (
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
        find.text(
          'No audio files available to play. Import a sound in Library.',
        ),
      );
      expect(
        find.text('rain.wav is no longer available. Choose another sound.'),
        findsNothing,
      );
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(start.onPressed, isNull);
      await app.dispose(tester);
    });
  });

  testWidgets('a missing remembered sound warns when other sounds remain', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final app = await _App.create();
      await app.open(tester);
      await _chooseSound(tester, 'rain.wav');
      await app.download('ocean.mp3');
      await File(app.sound!.reference).parent.delete(recursive: true);

      await app.relaunch(tester);
      await _pumpUntil(
        tester,
        find.text('rain.wav is no longer available. Choose another sound.'),
      );
      expect(
        find.text(
          'No audio files available to play. Import a sound in Library.',
        ),
        findsNothing,
      );
      final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start'),
      );
      expect(start.onPressed, isNull);
      await _chooseSound(tester, 'ocean.mp3');
      expect(
        find.text('rain.wav is no longer available. Choose another sound.'),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Start'))
            .onPressed,
        isNotNull,
      );
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

class _AppResolver implements PlaybackSourceResolver {
  _AppResolver(this._resolver);

  final PlaybackSourceResolver Function() _resolver;

  @override
  Future<PlayableMedia> resolve(AudioSource source) =>
      _resolver().resolve(source);
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
    if (media.kind == PlayableMediaKind.file &&
        !File(media.locator).existsSync()) {
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

class _ConnectedStore extends _StubSessionStore {
  @override
  Future<PCloudSession?> read() async =>
      const PCloudSession(authToken: 'test', apiHost: 'api.pcloud.com');
}
