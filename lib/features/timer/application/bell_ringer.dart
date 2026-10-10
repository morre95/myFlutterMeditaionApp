import '../../player/application/audio_command_queue.dart';
import '../../player/application/playback_source_resolver.dart';
import '../domain/bell_selection.dart';
import 'timer_bell_player.dart';

/// A built-in bell selection that names no bell in the catalog.
class UnavailableBellException implements Exception {
  const UnavailableBellException();
}

/// Rings a [BellSelection] on one [BellPlayer], serialising native commands so
/// a later stop always lands after an earlier play.
class BellRinger {
  BellRinger({
    required BellPlayer player,
    required PlaybackSourceResolver sourceResolver,
  }) : _player = player,
       _sourceResolver = sourceResolver;

  final BellPlayer _player;
  final PlaybackSourceResolver _sourceResolver;
  final _commands = AudioCommandQueue();

  /// Plays [bell] unless [canRun] turns false first. Throws
  /// [UnavailableBellException] for an unknown built-in bell, and rethrows
  /// resolution and playback failures.
  Future<void> ring(
    BellSelection bell, {
    required bool Function() canRun,
  }) async {
    if (bell.isCustom) {
      final media = await _sourceResolver.resolve(bell.source!);
      if (!canRun()) return;
      await _commands.run(() => _player.playMedia(media), canRun: canRun);
      return;
    }
    final builtIn = builtInBells.where((b) => b.id == bell.name).firstOrNull;
    if (builtIn == null) throw const UnavailableBellException();
    await _commands.run(
      () => _player.playAsset(builtIn.assetPath),
      canRun: canRun,
    );
  }

  Future<void> stop() => _commands.run(_player.stop);

  Future<void> dispose() =>
      _commands.disposePlayer(stop: _player.stop, dispose: _player.dispose);
}
