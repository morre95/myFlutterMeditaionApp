import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/library/application/local_wav_picker_service.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  group('PlatformFilePickerClient', () {
    late FilePickerPlatform original;
    late _FakeFilePickerPlatform platform;

    setUp(() {
      original = FilePickerPlatform.instance;
      platform = _FakeFilePickerPlatform();
      FilePickerPlatform.instance = platform;
    });

    tearDown(() => FilePickerPlatform.instance = original);

    test(
      'asks the system picker for audio so m4a files are selectable',
      () async {
        await const PlatformFilePickerClient().pickAudioFiles();

        // A custom extension filter maps m4a to a MIME type Android's
        // MediaStore does not report for .m4a, greying those files out.
        expect(platform.requestedType, FileType.audio);
        expect(platform.requestedExtensions, isNull);
      },
    );

    test('accepts every supported audio extension, including m4a', () async {
      platform.files = [
        for (final ext in ['wav', 'mp3', 'flac', 'ogg', 'm4a', 'aac'])
          _FakePlatformFile('/music/track.$ext'),
      ];

      final picked = await const PlatformFilePickerClient().pickAudioFiles();

      expect(picked.map((f) => f.name), [
        'track.wav',
        'track.mp3',
        'track.flac',
        'track.ogg',
        'track.m4a',
        'track.aac',
      ]);
    });

    test('drops picked files that are not supported audio', () async {
      platform.files = [
        _FakePlatformFile('/music/calm.m4a'),
        _FakePlatformFile('/music/notes.txt'),
        _FakePlatformFile('/music/voice.amr'),
      ];

      final picked = await const PlatformFilePickerClient().pickAudioFiles();

      expect(picked.map((f) => f.path), ['/music/calm.m4a']);
    });
  });

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

class _FakeFilePickerPlatform extends FilePickerPlatform {
  List<PlatformFile> files = [];
  FileType? requestedType;
  List<String>? requestedExtensions;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    requestedType = type;
    requestedExtensions = allowedExtensions;
    return files;
  }
}

final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile(String path) : uri = Uri.file(path);

  @override
  final Uri uri;

  @override
  String get name => uri.pathSegments.last;

  @override
  get xFile => throw UnimplementedError();

  @override
  Future<int> length() => throw UnimplementedError();

  @override
  Future<Uint8List> readAsBytes() => throw UnimplementedError();

  @override
  Stream<Uint8List> readAsByteStream() => throw UnimplementedError();
}
