import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/library/application/local_wav_picker_service.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  test(
    'maps picked wav files to read-only local audio source metadata',
    () async {
      final picker = FilePickerLocalAudioPicker(
        client: _FakeFilePickerClient([
          const LocalPickedFile(name: 'forest.wav', path: '/music/forest.wav'),
          const LocalPickedFile(name: 'rain.wav', path: '/music/rain.wav'),
        ]),
      );

      final sources = await picker.pickAudioFiles();

      expect(sources, hasLength(2));
      expect(sources.first.id, 'local:/music/forest.wav');
      expect(sources.first.kind, AudioSourceKind.localFile);
      expect(sources.first.displayName, 'forest.wav');
      expect(sources.first.reference, '/music/forest.wav');
      expect(sources.first.isSupportedAudio, isTrue);
    },
  );

  test(
    'maps picked mp3 files to read-only local audio source metadata',
    () async {
      final picker = FilePickerLocalAudioPicker(
        client: _FakeFilePickerClient([
          const LocalPickedFile(
            name: 'ambient.mp3',
            path: '/music/ambient.mp3',
          ),
        ]),
      );

      final sources = await picker.pickAudioFiles();

      expect(sources, hasLength(1));
      expect(sources.first.displayName, 'ambient.mp3');
      expect(sources.first.reference, '/music/ambient.mp3');
      expect(sources.first.isSupportedAudio, isTrue);
    },
  );
}

class _FakeFilePickerClient implements FilePickerClient {
  const _FakeFilePickerClient(this.files);

  final List<LocalPickedFile> files;

  @override
  Future<List<LocalPickedFile>> pickAudioFiles() async {
    return files;
  }
}
