import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  group('isSupportedAudio', () {
    for (final ext in ['wav', 'WAV', 'mp3', 'flac', 'ogg', 'm4a', 'aac']) {
      test('recognizes .$ext files by display name', () {
        final source = AudioSource(
          id: 'local-1',
          kind: AudioSourceKind.localFile,
          displayName: 'morning-meditation.$ext',
          reference: '/music/morning-meditation.$ext',
        );

        expect(source.isSupportedAudio, isTrue);
      });
    }

    test('rejects unsupported extension', () {
      const source = AudioSource(
        id: 'local-2',
        kind: AudioSourceKind.localFile,
        displayName: 'notes.txt',
        reference: '/docs/notes.txt',
      );

      expect(source.isSupportedAudio, isFalse);
    });
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
