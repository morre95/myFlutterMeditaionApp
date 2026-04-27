import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/player/application/playback_queue_controller.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  AudioSource source(String id) {
    return AudioSource(
      id: id,
      kind: AudioSourceKind.localFile,
      displayName: '$id.wav',
      reference: '/music/$id.wav',
    );
  }

  test('adds sources to the playback queue without changing references', () {
    final controller = PlaybackQueueController();
    final firstSource = source('first');
    final secondSource = source('second');

    final firstEntry = controller.add(firstSource);
    final secondEntry = controller.add(secondSource);

    expect(controller.entries, hasLength(2));
    expect(firstEntry.source.reference, '/music/first.wav');
    expect(secondEntry.source.reference, '/music/second.wav');
    expect(controller.entries.first.source, same(firstSource));
  });

  test('removes and reorders queue entries', () {
    final controller = PlaybackQueueController()
      ..add(source('first'))
      ..add(source('second'))
      ..add(source('third'));

    controller.reorder(oldIndex: 0, newIndex: 3);

    expect(controller.entries.map((entry) => entry.source.id), [
      'second',
      'third',
      'first',
    ]);

    controller.remove(controller.entries[1].id);

    expect(controller.entries.map((entry) => entry.source.id), [
      'second',
      'first',
    ]);
  });
}
