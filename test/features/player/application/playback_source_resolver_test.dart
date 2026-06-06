import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/player/application/playback_source_resolver.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  const resolver = LocalPlaybackSourceResolver();

  test('resolves a local file to a file locator', () async {
    const source = AudioSource(
      id: 'local:/music/rain.wav',
      kind: AudioSourceKind.localFile,
      displayName: 'rain.wav',
      reference: '/music/rain.wav',
    );

    final media = await resolver.resolve(source);

    expect(media.kind, PlayableMediaKind.file);
    expect(media.locator, '/music/rain.wav');
  });

  test('throws for unsupported remote sources', () async {
    const source = AudioSource(
      id: 'pcloud:123',
      kind: AudioSourceKind.pCloud,
      displayName: 'remote.mp3',
      reference: '123',
    );

    expect(
      () => resolver.resolve(source),
      throwsA(isA<UnsupportedSourceException>()),
    );
  });
}
