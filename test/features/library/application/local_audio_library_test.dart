import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/library/application/local_audio_library.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  test(
    'cleanup failure keeps safe import error and does not leave batch sounds available',
    () async {
      final root = await Directory.systemTemp.createTemp('cleanup-library-');
      addTearDown(() => root.delete(recursive: true));
      final original = await File(
        '${root.path}/rain.wav',
      ).writeAsBytes([1, 2, 3]);
      final libraryRoot = Directory('${root.path}/library');
      var failedDeletion = false;
      final library = LocalAudioLibrary(
        directory: libraryRoot,
        deleteDirectory: (directory) async {
          if (!directory.path.split('/').last.startsWith('.') &&
              !failedDeletion) {
            failedDeletion = true;
            throw const FileSystemException('storage unavailable');
          }
          await directory.delete(recursive: true);
        },
      );
      final source = AudioSource(
        id: 'original',
        kind: AudioSourceKind.localFile,
        displayName: 'rain.wav',
        reference: original.path,
      );
      await expectLater(
        library.importSources([
          source,
          source,
          source.copyWith(reference: '${root.path}/missing.wav'),
        ]),
        throwsA(
          isA<AudioImportFailure>().having(
            (failure) => failure.code,
            'code',
            'IMPORT_FAILED',
          ),
        ),
      );
      expect(
        await LocalAudioLibrary(directory: libraryRoot).loadSounds(),
        isEmpty,
      );
    },
  );
  test('corrupt metadata does not hide healthy imported sounds', () async {
    final root = await Directory.systemTemp.createTemp('corrupt-library-');
    addTearDown(() => root.delete(recursive: true));
    final file = await File('${root.path}/rain.wav').writeAsBytes([1, 2, 3]);
    final libraryRoot = Directory('${root.path}/library');
    final library = LocalAudioLibrary(directory: libraryRoot);
    final sound = (await library.importSources([
      AudioSource(
        id: 'original',
        kind: AudioSourceKind.localFile,
        displayName: 'rain.wav',
        reference: file.path,
      ),
    ])).single;
    await Directory('${libraryRoot.path}/missing').create();
    final corrupt = await Directory('${libraryRoot.path}/corrupt').create();
    await File('${corrupt.path}/sound.json').writeAsString('{');
    expect((await library.loadSounds()).map((source) => source.id), [sound.id]);
  });
  test('unavailable app storage reports a safe import failure', () async {
    final root = await Directory.systemTemp.createTemp('unavailable-library-');
    addTearDown(() => root.delete(recursive: true));
    final file = await File('${root.path}/rain.wav').writeAsBytes([1, 2, 3]);
    final library = LocalAudioLibrary(directory: Directory(file.path));
    await expectLater(
      library.importSources([
        AudioSource(
          id: 'original',
          kind: AudioSourceKind.localFile,
          displayName: 'rain.wav',
          reference: file.path,
        ),
      ]),
      throwsA(
        isA<AudioImportFailure>().having(
          (failure) => failure.code,
          'code',
          'IMPORT_FAILED',
        ),
      ),
    );
    expect(await file.readAsBytes(), [1, 2, 3]);
  });
  test(
    'restored catalog follows relocated storage and excludes missing copies',
    () async {
      final root = await Directory.systemTemp.createTemp('relocated-library-');
      addTearDown(() => root.delete(recursive: true));
      final original = await File(
        '${root.path}/rain.wav',
      ).writeAsBytes([4, 5, 6]);
      final directory = Directory('${root.path}/library');
      final imported = await LocalAudioLibrary(directory: directory)
          .importSources([
            AudioSource(
              id: 'original',
              kind: AudioSourceKind.localFile,
              displayName: 'rain.wav',
              reference: original.path,
            ),
          ]);
      final moved = await directory.rename('${root.path}/moved');
      final restoredLibrary = LocalAudioLibrary(directory: moved);
      final restored = await restoredLibrary.loadSounds();
      expect(restored.single.id, imported.single.id);
      expect(await File(restored.single.reference).readAsBytes(), [4, 5, 6]);
      await File(restored.single.reference).delete();
      expect(await restoredLibrary.loadSounds(), isEmpty);
    },
  );
  test(
    'failed batch preserves existing sounds and publishes none of the batch',
    () async {
      final root = await Directory.systemTemp.createTemp('batch-library-');
      addTearDown(() => root.delete(recursive: true));
      final file = await File('${root.path}/rain.wav').writeAsBytes([1, 2, 3]);
      final library = LocalAudioLibrary(
        directory: Directory('${root.path}/library'),
      );
      final source = AudioSource(
        id: 'original',
        kind: AudioSourceKind.localFile,
        displayName: 'rain.wav',
        reference: file.path,
      );
      final existing = await library.importSources([source]);
      await expectLater(
        library.importSources([
          source,
          source.copyWith(reference: '${root.path}/missing.wav'),
        ]),
        throwsA(isA<AudioImportFailure>()),
      );
      expect((await library.loadSounds()).map((sound) => sound.id), [
        existing.single.id,
      ]);
      expect(await file.readAsBytes(), [1, 2, 3]);
    },
  );
  test(
    'import survives restart and removal of the original with exact bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('local-library-');
      addTearDown(() => root.delete(recursive: true));
      final original = await File(
        '${root.path}/forest.wav',
      ).writeAsBytes([1, 2, 3, 4]);
      final library = LocalAudioLibrary(
        directory: Directory('${root.path}/library'),
      );
      final imported = await library.importSources([
        AudioSource(
          id: 'legacy',
          kind: AudioSourceKind.localFile,
          displayName: 'forest.wav',
          reference: original.path,
        ),
      ]);
      await original.delete();
      final restored = await LocalAudioLibrary(
        directory: Directory('${root.path}/library'),
      ).loadSounds();
      expect(restored.single.toJson(), imported.single.toJson());
      expect(restored.single.storedSize, 4);
      expect(restored.single.id, isNot('legacy'));
      expect(restored.single.displayName, 'forest.wav');
      expect(await File(restored.single.reference).readAsBytes(), [1, 2, 3, 4]);
    },
  );
  test('cancellation during copying never publishes a partial sound', () async {
    final root = await Directory.systemTemp.createTemp('canceled-library-');
    addTearDown(() => root.delete(recursive: true));
    final original = await File(
      '${root.path}/rain.wav',
    ).writeAsBytes([1, 2, 3, 4]);
    final bytes = StreamController<List<int>>();
    final entered = Completer<void>();
    final cancel = AudioImportCancellation();
    final library = LocalAudioLibrary(
      directory: root,
      readFile: (_) {
        entered.complete();
        return bytes.stream;
      },
    );
    final importing = library.importSources([
      AudioSource(
        id: 'source',
        kind: AudioSourceKind.localFile,
        displayName: 'rain.wav',
        reference: original.path,
      ),
    ], cancellation: cancel);
    final assertion = expectLater(
      importing,
      throwsA(
        isA<AudioImportFailure>().having(
          (e) => e.code,
          'code',
          'IMPORT_CANCELED',
        ),
      ),
    );
    await entered.future;
    bytes.add(await original.readAsBytes());
    expect(await library.loadSounds(), isEmpty);
    cancel.cancel();
    await bytes.close();
    await assertion;
    expect(await library.loadSounds(), isEmpty);
  });

  test('read failure after partial bytes leaves no imported sound', () async {
    final root = await Directory.systemTemp.createTemp('failed-library-');
    addTearDown(() => root.delete(recursive: true));
    final library = LocalAudioLibrary(
      directory: root,
      readFile: (_) async* {
        yield [1, 2];
        throw const FileSystemException('unavailable');
      },
    );
    await expectLater(
      library.importSources([
        const AudioSource(
          id: 'source',
          kind: AudioSourceKind.localFile,
          displayName: 'rain.wav',
          reference: '/missing',
        ),
      ]),
      throwsA(isA<AudioImportFailure>()),
    );
    expect(await LocalAudioLibrary(directory: root).loadSounds(), isEmpty);
  });
  test('unsupported and empty files cannot become available sounds', () async {
    final root = await Directory.systemTemp.createTemp('invalid-library-');
    addTearDown(() => root.delete(recursive: true));
    final file = await File('${root.path}/empty.wav').writeAsBytes([]);
    final library = LocalAudioLibrary(
      directory: Directory('${root.path}/library'),
    );
    for (final name in ['empty.wav', 'image.png']) {
      await expectLater(
        library.importSources([
          AudioSource(
            id: 'source',
            kind: AudioSourceKind.localFile,
            displayName: name,
            reference: file.path,
          ),
        ]),
        throwsA(isA<AudioImportFailure>()),
      );
    }
    expect(await library.loadSounds(), isEmpty);
  });
}
