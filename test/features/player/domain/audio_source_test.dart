import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  test('recognizes wav files by display name', () {
    const source = AudioSource(
      id: 'local-1',
      kind: AudioSourceKind.localFile,
      displayName: 'morning-meditation.WAV',
      reference: '/music/morning-meditation.WAV',
    );

    expect(source.isWav, isTrue);
  });

  test('preserves read-only provider reference metadata', () {
    const source = AudioSource(
      id: 'pcloud-1',
      kind: AudioSourceKind.pCloud,
      displayName: 'rain.wav',
      reference: 'pcloud:file:123',
      duration: Duration(minutes: 20),
    );

    final renamedMetadata = source.copyWith(displayName: 'soft-rain.wav');

    expect(renamedMetadata.reference, source.reference);
    expect(renamedMetadata.kind, AudioSourceKind.pCloud);
    expect(source.displayName, 'rain.wav');
  });
}
