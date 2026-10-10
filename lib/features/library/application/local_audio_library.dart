import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../shared/domain/audio_source.dart';

/// A durable catalog independent of playlists. Only completed copies are listed.
class LocalAudioLibrary {
  LocalAudioLibrary({
    Directory? directory,
    Stream<List<int>> Function(String)? readFile,
    Future<void> Function(Directory)? deleteDirectory,
  }) : _directory = directory,
       _readFile = readFile ?? ((locator) => File(locator).openRead()),
       _deleteDirectory =
           deleteDirectory ??
           ((directory) async {
             await directory.delete(recursive: true);
           });

  final Directory? _directory;
  final Stream<List<int>> Function(String) _readFile;
  final Future<void> Function(Directory) _deleteDirectory;

  Future<Directory> _root() async {
    final root =
        _directory ??
        Directory(
          path.join((await getApplicationSupportDirectory()).path, 'sounds'),
        );
    return root.create(recursive: true);
  }

  Future<List<AudioSource>> loadSounds() async {
    final root = await _root();
    final sounds = <AudioSource>[];
    await for (final entry in root.list()) {
      if (entry is! Directory || path.basename(entry.path).startsWith('.')) {
        continue;
      }
      try {
        final json =
            jsonDecode(
                  await File(
                    path.join(entry.path, 'sound.json'),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final sound = AudioSource.fromJson(json);
        final file = File(
          path.join(
            entry.path,
            'audio${path.extension(sound.displayName).toLowerCase()}',
          ),
        );
        if (!sound.isSupportedAudio ||
            !await file.exists() ||
            sound.storedSize == null ||
            await file.length() != sound.storedSize) {
          continue;
        }
        sounds.add(sound.copyWith(reference: file.path));
      } catch (error) {
        if (error is! FileSystemException &&
            error is! FormatException &&
            error is! TypeError) {
          rethrow;
        }
        debugPrint('Skipped unavailable local sound (${error.runtimeType}).');
      }
    }
    return sounds;
  }

  Future<List<AudioSource>> importSources(
    List<AudioSource> sources, {
    AudioImportCancellation? cancellation,
  }) async {
    if (sources.isEmpty) return [];
    final created = <Directory>[];
    try {
      final root = await _root();
      final sounds = <AudioSource>[];
      for (final source in sources) {
        cancellation?._check();
        if (source.kind != AudioSourceKind.localFile ||
            !source.isSupportedAudio) {
          throw const AudioImportFailure(
            'UNSUPPORTED_AUDIO',
            'Choose a wav, mp3, flac, ogg, m4a, or aac audio file.',
          );
        }
        final id = List.generate(
          16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        final staging = await Directory(path.join(root.path, '.$id')).create();
        created.add(staging);
        final destination = path.join(root.path, id);
        final audioName =
            'audio${path.extension(source.displayName).toLowerCase()}';
        final output = await File(
          path.join(staging.path, audioName),
        ).open(mode: FileMode.write);
        try {
          await for (final chunk in _readFile(source.reference)) {
            cancellation?._check();
            await output.writeFrom(chunk);
          }
          await output.flush();
        } finally {
          await output.close();
        }
        cancellation?._check();
        final size = await File(path.join(staging.path, audioName)).length();
        if (size == 0) {
          throw const AudioImportFailure(
            'EMPTY_AUDIO',
            'The selected audio file is empty. Choose another file.',
          );
        }
        final sound = AudioSource(
          id: 'import:$id',
          kind: AudioSourceKind.localFile,
          displayName: source.displayName,
          reference: path.join(destination, audioName),
          storedSize: size,
        );
        await File(
          path.join(staging.path, 'sound.json'),
        ).writeAsString(jsonEncode(sound.toJson()), flush: true);
        cancellation?._check();
        final committed = await staging.rename(destination);
        created[created.length - 1] = committed;
        cancellation?._check();
        sounds.add(sound);
      }
      return sounds;
    } catch (error) {
      for (final directory in created.reversed) {
        // Invalidate catalog availability before deleting a completed copy.
        // If storage prevents directory removal, its audio is no longer listed.
        if (!path.basename(directory.path).startsWith('.')) {
          try {
            final metadata = File(path.join(directory.path, 'sound.json'));
            if (await metadata.exists()) {
              await metadata.delete();
            }
          } catch (cleanupError) {
            debugPrint(
              'Local sound invalidation failed (${cleanupError.runtimeType}).',
            );
          }
        }
        try {
          if (await directory.exists()) {
            await _deleteDirectory(directory);
          }
        } catch (cleanupError) {
          debugPrint(
            'Local sound cleanup failed (${cleanupError.runtimeType}).',
          );
        }
      }
      debugPrint('Local audio import failed (${error.runtimeType}).');
      if (error is AudioImportFailure) rethrow;
      throw const AudioImportFailure(
        'IMPORT_FAILED',
        'Could not import audio. Check that the file is available and storage has space.',
      );
    }
  }
}

class AudioImportCancellation {
  bool _canceled = false;
  void cancel() => _canceled = true;
  void _check() {
    if (_canceled) {
      throw const AudioImportFailure(
        'IMPORT_CANCELED',
        'Audio import canceled.',
      );
    }
  }
}

class AudioImportFailure implements Exception {
  const AudioImportFailure(this.code, this.message);
  final String code;
  final String message;
}
