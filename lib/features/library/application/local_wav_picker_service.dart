import 'package:file_picker/file_picker.dart';

import '../../../shared/domain/audio_source.dart';

abstract class LocalWavPicker {
  Future<List<AudioSource>> pickWavFiles();
}

class FilePickerLocalWavPicker implements LocalWavPicker {
  FilePickerLocalWavPicker({FilePickerClient? client})
    : _client = client ?? const PlatformFilePickerClient();

  final FilePickerClient _client;

  @override
  Future<List<AudioSource>> pickWavFiles() async {
    final files = await _client.pickWavFiles();
    return files.map(_toAudioSource).toList(growable: false);
  }

  AudioSource _toAudioSource(LocalPickedFile file) {
    return AudioSource(
      id: 'local:${file.path}',
      kind: AudioSourceKind.localFile,
      displayName: file.name,
      reference: file.path,
    );
  }
}

abstract class FilePickerClient {
  Future<List<LocalPickedFile>> pickWavFiles();
}

class PlatformFilePickerClient implements FilePickerClient {
  const PlatformFilePickerClient();

  @override
  Future<List<LocalPickedFile>> pickWavFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['wav'],
      dialogTitle: 'Select WAV files',
      withData: false,
      withReadStream: false,
    );

    if (result == null) {
      return const <LocalPickedFile>[];
    }

    return result.files
        .where((file) => file.path != null && _isWav(file))
        .map((file) => LocalPickedFile(name: file.name, path: file.path!))
        .toList(growable: false);
  }

  bool _isWav(PlatformFile file) {
    return file.extension?.toLowerCase() == 'wav' ||
        file.name.toLowerCase().endsWith('.wav');
  }
}

class LocalPickedFile {
  const LocalPickedFile({required this.name, required this.path});

  final String name;
  final String path;
}
