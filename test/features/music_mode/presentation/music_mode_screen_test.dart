import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/library/application/local_wav_picker_service.dart';
import 'package:my_meditation_app/features/music_mode/presentation/music_mode_screen.dart';
import 'package:my_meditation_app/features/player/application/local_audio_playback_controller.dart';
import 'package:my_meditation_app/features/player/application/playback_queue_controller.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  testWidgets('adds picked audio files to the Music Mode queue', (tester) async {
    final queueController = PlaybackQueueController();
    final player = _FakeLocalAudioPlayer();
    final playbackController = LocalAudioPlaybackController(player: player);

    await tester.pumpWidget(
      MaterialApp(
        home: MusicModeScreen(
          queueController: queueController,
          picker: const _FakeLocalAudioFilePicker([
            AudioSource(
              id: 'first',
              kind: AudioSourceKind.localFile,
              displayName: 'first.wav',
              reference: '/music/first.wav',
            ),
            AudioSource(
              id: 'second',
              kind: AudioSourceKind.localFile,
              displayName: 'second.wav',
              reference: '/music/second.wav',
            ),
          ]),
          playbackController: playbackController,
        ),
      ),
    );

    expect(find.text('No audio files queued yet.'), findsOneWidget);

    await tester.tap(find.text('Add audio files'));
    await tester.pump();

    expect(find.text('first.wav'), findsOneWidget);
    expect(find.text('second.wav'), findsOneWidget);
    expect(find.text('Added 2 audio files to the queue.'), findsOneWidget);

    await tester.tap(find.byTooltip('Play first.wav'));
    await tester.pump();

    expect(player.loadedPath, '/music/first.wav');
    expect(find.text('Playing.'), findsOneWidget);
    expect(find.text('Current: first.wav'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove first.wav'));
    await tester.pump();

    expect(find.text('first.wav'), findsNothing);
    expect(find.text('second.wav'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pump();

    expect(find.text('No audio files queued yet.'), findsOneWidget);

    playbackController.dispose();
    queueController.dispose();
  });
}

class _FakeLocalAudioFilePicker implements LocalAudioFilePicker {
  const _FakeLocalAudioFilePicker(this.sources);

  final List<AudioSource> sources;

  @override
  Future<List<AudioSource>> pickAudioFiles() async {
    return sources;
  }
}

class _FakeLocalAudioPlayer implements LocalAudioPlayer {
  final StreamController<bool> _completedController =
      StreamController<bool>.broadcast();

  String? loadedPath;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Future<void> load(String path) async {
    loadedPath = path;
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {
    unawaited(_completedController.close());
  }
}
