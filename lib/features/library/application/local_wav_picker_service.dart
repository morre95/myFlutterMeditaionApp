import 'package:file_picker/file_picker.dart';

import '../../../shared/domain/audio_source.dart';

const _supportedExtensions = ['wav', 'mp3', 'flac', 'ogg', 'm4a', 'aac'];

abstract class LocalAudioFilePicker {
  Future<List<AudioSource>> pickAudioFiles();
}

class FilePickerLocalAudioPicker implements LocalAudioFilePicker {
  FilePickerLocalAudioPicker({FilePickerClient? client})
    : _client = client ?? const PlatformFilePickerClient();

  final FilePickerClient _client;

  @override
  Future<List<AudioSource>> pickAudioFiles() async {
    final files = await _client.pickAudioFiles();
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
  Future<List<LocalPickedFile>> pickAudioFiles();
}

class PlatformFilePickerClient implements FilePickerClient {
  const PlatformFilePickerClient();

  @override
  Future<List<LocalPickedFile>> pickAudioFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _supportedExtensions,
      dialogTitle: 'Select audio files',
      withData: false,
      withReadStream: false,
    );

    if (result == null) {
      return const <LocalPickedFile>[];
    }

    return result.files
        .where((file) => file.path != null && _isSupportedAudio(file))
        .map((file) => LocalPickedFile(name: file.name, path: file.path!))
        .toList(growable: false);
  }

  bool _isSupportedAudio(PlatformFile file) {
    final ext = (file.extension ?? '').toLowerCase();
    if (ext.isNotEmpty) {
      return _supportedExtensions.contains(ext);
    }
    return _supportedExtensions.any(
      (e) => file.name.toLowerCase().endsWith('.$e'),
    );
  }
}

class LocalPickedFile {
  const LocalPickedFile({required this.name, required this.path});

  final String name;
  final String path;
}
