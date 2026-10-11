import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/app/app_dependencies.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_download_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_session_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';
import 'package:my_meditation_app/features/library/application/device_sound_catalog.dart';
import 'package:my_meditation_app/features/library/application/local_audio_library.dart';
import 'package:my_meditation_app/features/player/application/local_audio_playback_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/features/player/domain/queue_entry.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Music playback keeps its sound until playback stops', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('app-deps-');
    addTearDown(() => root.delete(recursive: true));
    final original = await File('${root.path}/waves.wav').writeAsBytes([1]);
    final library = LocalAudioLibrary(
      directory: Directory('${root.path}/sounds'),
    );
    final sound = (await library.importSources([
      AudioSource(
        id: 'original',
        kind: AudioSourceKind.localFile,
        displayName: 'waves.wav',
        reference: original.path,
      ),
    ])).single;
    final music = LocalAudioPlaybackController(player: _FakeLocalAudioPlayer());
    final deps = AppDependencies(
      localAudioLibrary: library,
      playbackController: music,
      pcloudDownloadStore: PCloudDownloadStore(
        directory: Directory('${root.path}/pcloud_downloads'),
      ),
      pcloudAuthController: PCloudAuthController(store: _StubSessionStore()),
    );
    addTearDown(deps.dispose);

    await music.play(
      QueueEntry(id: 't1', source: sound, addedAt: DateTime(2026)),
    );
    await expectLater(
      deps.deviceSoundCatalog.remove(sound),
      throwsA(isA<SoundInUseException>()),
    );

    await music.stop();
    await deps.deviceSoundCatalog.remove(sound);
    expect(await deps.deviceSoundCatalog.load(), isEmpty);
  });
}

class _StubSessionStore implements PCloudSessionStore {
  @override
  Future<PCloudSession?> read() async => null;
  @override
  Future<void> write(PCloudSession session) async {}
  @override
  Future<void> clear() async {}
}

class _FakeLocalAudioPlayer implements LocalAudioPlayer {
  final _completed = StreamController<bool>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();

  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration> get durationStream => _durations.stream;
  @override
  Future<void> load(PlayableMedia media) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double volume) async {}

  @override
  void dispose() {
    unawaited(_completed.close());
    unawaited(_positions.close());
    unawaited(_durations.close());
  }
}
