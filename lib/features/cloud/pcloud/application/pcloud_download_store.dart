import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../../shared/domain/audio_source.dart';

/// A committed offline copy: the pCloud source (identity and provider
/// reference unchanged, plus `storedSize`) and the app-owned audio [path].
class PCloudOfflineCopy {
  const PCloudOfflineCopy({required this.source, required this.path});

  final AudioSource source;
  final String path;
}

/// Durable app-owned copies of pCloud files, one directory per file id.
///
/// Like local imports, audio and metadata are flushed in a hidden staging
/// directory and published by rename, so only complete copies are listed.
class PCloudDownloadStore {
  PCloudDownloadStore({
    Directory? directory,
    Future<void> Function(RandomAccessFile, List<int>)? writeChunk,
  }) : _directory = directory,
       _writeChunk = writeChunk ?? ((file, chunk) => file.writeFrom(chunk));

  final Directory? _directory;
  final Future<void> Function(RandomAccessFile, List<int>) _writeChunk;

  Future<Directory> _root() async {
    final root =
        _directory ??
        Directory(
          path.join(
            (await getApplicationSupportDirectory()).path,
            'pcloud_downloads',
          ),
        );
    return root.create(recursive: true);
  }

  static String _audioName(AudioSource source) =>
      'audio${path.extension(source.displayName).toLowerCase()}';

  /// Lists complete copies and removes staging left by interrupted transfers.
  Future<List<PCloudOfflineCopy>> load() async {
    final root = await _root();
    final copies = <PCloudOfflineCopy>[];
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      if (path.basename(entry.path).startsWith('.')) {
        await entry.delete(recursive: true);
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
        final source = AudioSource.fromJson(json);
        final audio = File(path.join(entry.path, _audioName(source)));
        if (source.kind != AudioSourceKind.pCloud ||
            path.basename(entry.path) != source.reference ||
            !await audio.exists() ||
            await audio.length() != source.storedSize) {
          continue;
        }
        copies.add(PCloudOfflineCopy(source: source, path: audio.path));
      } catch (error) {
        if (error is! FileSystemException &&
            error is! FormatException &&
            error is! TypeError) {
          rethrow;
        }
        debugPrint(
          'Skipped unavailable pCloud download (${error.runtimeType}).',
        );
      }
    }
    return copies;
  }

  /// Writes [bytes] as the offline copy of [source] and commits it.
  Future<PCloudOfflineCopy> save(
    AudioSource source,
    Stream<List<int>> bytes,
  ) async {
    final root = await _root();
    final suffix = Random.secure().nextInt(1 << 32).toRadixString(16);
    final staging = await Directory(
      path.join(root.path, '.${source.reference}-$suffix'),
    ).create();
    try {
      final audioName = _audioName(source);
      final audio = File(path.join(staging.path, audioName));
      final output = await audio.open(mode: FileMode.write);
      try {
        await for (final chunk in bytes) {
          await _writeChunk(output, chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      final stored = source.copyWith(storedSize: await audio.length());
      await File(
        path.join(staging.path, 'sound.json'),
      ).writeAsString(jsonEncode(stored.toJson()), flush: true);
      // Only an incomplete copy, never listed as available, can be here.
      final destination = Directory(path.join(root.path, source.reference));
      if (await destination.exists()) {
        await destination.delete(recursive: true);
      }
      final committed = await staging.rename(destination.path);
      return PCloudOfflineCopy(
        source: stored,
        path: path.join(committed.path, audioName),
      );
    } catch (_) {
      await staging.delete(recursive: true);
      rethrow;
    }
  }
}
