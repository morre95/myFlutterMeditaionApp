import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/library/application/local_wav_picker_service.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  test(
    'maps picked wav files to read-only local audio source metadata',
    () async {
      final picker = FilePickerLocalWavPicker(
        client: _FakeFilePickerClient([
          const LocalPickedFile(name: 'forest.wav', path: '/music/forest.wav'),
          const LocalPickedFile(name: 'rain.wav', path: '/music/rain.wav'),
        ]),
      );

      final sources = await picker.pickWavFiles();

      expect(sources, hasLength(2));
      expect(sources.first.id, 'local:/music/forest.wav');
      expect(sources.first.kind, AudioSourceKind.localFile);
      expect(sources.first.displayName, 'forest.wav');
      expect(sources.first.reference, '/music/forest.wav');
      expect(sources.first.isWav, isTrue);
    },
  );
}

class _FakeFilePickerClient implements FilePickerClient {
  const _FakeFilePickerClient(this.files);

  final List<LocalPickedFile> files;

  @override
  Future<List<LocalPickedFile>> pickWavFiles() async {
    return files;
  }
}
