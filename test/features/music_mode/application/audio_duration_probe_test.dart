import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/music_mode/application/audio_duration_probe.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  const localSource = AudioSource(
    id: 'local:/music/rain.wav',
    kind: AudioSourceKind.localFile,
    displayName: 'rain.wav',
    reference: '/music/rain.wav',
  );

  test('returns duration reported via onDurationChanged after playback', () async {
    final player = _FakeProbeAudioPlayer(
      durationOnResume: const Duration(minutes: 4),
    );
    final probe = AudioPlayersDurationProbe(playerFactory: () => player);

    final result = await probe.durationOf(localSource);

    expect(result, const Duration(minutes: 4));
    expect(player.loadedPath, '/music/rain.wav');
    expect(player.resumed, isTrue);
    expect(player.disposed, isTrue);
  });

  test('uses immediate getDuration when it is already available', () async {
    final player = _FakeProbeAudioPlayer(
      immediateDuration: const Duration(seconds: 90),
    );
    final probe = AudioPlayersDurationProbe(playerFactory: () => player);

    final result = await probe.durationOf(localSource);

    expect(result, const Duration(seconds: 90));
    expect(player.disposed, isTrue);
  });

  test('returns null for a non-local source without creating a player', () async {
    var created = false;
    final probe = AudioPlayersDurationProbe(
      playerFactory: () {
        created = true;
        return _FakeProbeAudioPlayer();
      },
    );

    final result = await probe.durationOf(
      const AudioSource(
        id: 'pcloud:1',
        kind: AudioSourceKind.pCloud,
        displayName: 'remote.wav',
        reference: '1',
      ),
    );

    expect(result, isNull);
    expect(created, isFalse);
  });

  test('returns null when no duration becomes available before timeout', () async {
    final player = _FakeProbeAudioPlayer();
    final probe = AudioPlayersDurationProbe(
      playerFactory: () => player,
      timeout: Duration.zero,
    );

    final result = await probe.durationOf(localSource);

    expect(result, isNull);
    expect(player.disposed, isTrue);
  });

  test('returns null and still disposes the player on error', () async {
    final player = _FakeProbeAudioPlayer(throwOnSetSource: true);
    final probe = AudioPlayersDurationProbe(playerFactory: () => player);

    final result = await probe.durationOf(localSource);

    expect(result, isNull);
    expect(player.disposed, isTrue);
  });
}

class _FakeProbeAudioPlayer implements ProbeAudioPlayer {
  _FakeProbeAudioPlayer({
    this.durationOnResume,
    this.immediateDuration,
    this.throwOnSetSource = false,
  });

  final Duration? durationOnResume;
  final Duration? immediateDuration;
  final bool throwOnSetSource;

  final StreamController<Duration> _controller =
      StreamController<Duration>.broadcast();

  String? loadedPath;
  bool resumed = false;
  bool disposed = false;

  @override
  Stream<Duration> get onDurationChanged => _controller.stream;

  @override
  Future<void> configureForSilentProbe() async {}

  @override
  Future<void> setSourceDeviceFile(String path) async {
    if (throwOnSetSource) throw StateError('cannot set source');
    loadedPath = path;
  }

  @override
  Future<Duration?> getDuration() async => immediateDuration;

  @override
  Future<void> resume() async {
    resumed = true;
    final duration = durationOnResume;
    if (duration != null) _controller.add(duration);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
}
