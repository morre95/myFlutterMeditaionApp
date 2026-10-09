import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/player/application/local_audio_playback_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/features/player/domain/queue_entry.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  test('loads and plays a queue entry', () async {
    final player = _FakeLocalAudioPlayer();
    final controller = LocalAudioPlaybackController(player: player);
    final entry = _entry('rain');

    await controller.play(entry);

    expect(player.loadedPath, '/music/rain.wav');
    expect(player.playCount, 1);
    expect(controller.state.status, LocalPlaybackStatus.playing);
    expect(controller.state.currentEntry, same(entry));

    controller.dispose();
  });

  test('pauses, stops, and marks completion', () async {
    final player = _FakeLocalAudioPlayer();
    final controller = LocalAudioPlaybackController(player: player);

    await controller.play(_entry('forest'));
    await controller.pause();

    expect(player.pauseCount, 1);
    expect(controller.state.status, LocalPlaybackStatus.paused);

    player.complete();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, LocalPlaybackStatus.completed);

    await controller.stop();

    expect(player.stopCount, 1);
    expect(controller.state.status, LocalPlaybackStatus.idle);

    controller.dispose();
  });

  test('tracks duration, position, and seeks within current track', () async {
    final player = _FakeLocalAudioPlayer();
    final controller = LocalAudioPlaybackController(player: player);

    await controller.play(_entry('ocean'));
    player.setDuration(const Duration(minutes: 3));
    player.setPosition(const Duration(seconds: 42));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.duration, const Duration(minutes: 3));
    expect(controller.state.position, const Duration(seconds: 42));

    await controller.seek(const Duration(minutes: 2));

    expect(player.seekPosition, const Duration(minutes: 2));
    expect(controller.state.position, const Duration(minutes: 2));

    controller.dispose();
  });
  test('disposing playback cancels a source still being resolved', () async {
    final player = _FakeLocalAudioPlayer();
    final resolver = _DeferredResolver();
    final controller = LocalAudioPlaybackController(
      player: player,
      resolver: resolver,
    );
    final pending = controller.play(_entry('rain'));
    controller.dispose();
    resolver.result.complete(const PlayableMedia.file('/music/rain.wav'));
    await pending;
    expect(player.playCount, 0);
    expect(player.disposed, isTrue);
  });
  test('Stop cancels a source still resolving before it can play', () async {
    final player = _FakeLocalAudioPlayer();
    final resolver = _DeferredResolver();
    final controller = LocalAudioPlaybackController(
      player: player,
      resolver: resolver,
    );
    final pending = controller.play(_entry('rain'));
    await controller.stop();
    expect(controller.state.status, LocalPlaybackStatus.idle);
    resolver.result.complete(const PlayableMedia.file('/music/rain.wav'));
    await pending;
    expect(player.playCount, 0);
    expect(controller.state.status, LocalPlaybackStatus.idle);
    controller.dispose();
  });

  test('Stop cancels an audio load that is still pending', () async {
    final player = _FakeLocalAudioPlayer();
    final load = player.loadResult = Completer<void>();
    final controller = LocalAudioPlaybackController(player: player);
    final pending = controller.play(_entry('rain'));
    await Future<void>.delayed(Duration.zero);
    await controller.stop();
    expect(controller.state.status, LocalPlaybackStatus.idle);
    load.complete();
    await pending;
    expect(player.playCount, 0);
    expect(controller.state.status, LocalPlaybackStatus.idle);
    controller.dispose();
  });

  test('Stop discards an obsolete source resolution error', () async {
    final player = _FakeLocalAudioPlayer();
    final resolver = _DeferredResolver();
    final controller = LocalAudioPlaybackController(
      player: player,
      resolver: resolver,
    );
    final pending = controller.play(_entry('rain'));
    await controller.stop();
    resolver.result.completeError(StateError('source unavailable'));
    await pending;
    expect(controller.state.status, LocalPlaybackStatus.idle);
    expect(controller.state.errorMessage, isNull);
    controller.dispose();
  });
}

QueueEntry _entry(String id) {
  return QueueEntry(
    id: 'queue-$id',
    source: AudioSource(
      id: id,
      kind: AudioSourceKind.localFile,
      displayName: '$id.wav',
      reference: '/music/$id.wav',
    ),
    addedAt: DateTime(2026),
  );
}

class _FakeLocalAudioPlayer implements LocalAudioPlayer {
  final StreamController<bool> _completedController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  Completer<void>? loadResult;
  String? loadedPath;
  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  Duration? seekPosition;
  bool disposed = false;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Future<void> load(PlayableMedia media) async {
    loadedPath = media.locator;
    await loadResult?.future;
  }

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  Future<void> seek(Duration position) async {
    seekPosition = position;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  void setPosition(Duration position) {
    _positionController.add(position);
  }

  void setDuration(Duration duration) {
    _durationController.add(duration);
  }

  void complete() {
    _completedController.add(true);
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_completedController.close());
    unawaited(_positionController.close());
    unawaited(_durationController.close());
  }
}

class _DeferredResolver implements PlaybackSourceResolver {
  final result = Completer<PlayableMedia>();
  @override
  Future<PlayableMedia> resolve(AudioSource source) => result.future;
}
