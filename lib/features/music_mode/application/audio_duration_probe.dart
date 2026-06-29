import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';

import '../../../shared/domain/audio_source.dart';

/// Reads the duration of an audio source without playing it audibly. Abstracted
/// so the UI can be tested without the audio plugin.
abstract interface class AudioDurationProbe {
  Future<Duration?> durationOf(AudioSource source);
}

/// The minimal player surface the probe needs, kept behind an interface so the
/// probe can be unit-tested without the audio plugin.
abstract interface class ProbeAudioPlayer {
  Stream<Duration> get onDurationChanged;

  /// Mutes the player and stops it from looping so a probe is silent and
  /// short-lived.
  Future<void> configureForSilentProbe();

  Future<void> setSourceDeviceFile(String path);

  Future<Duration?> getDuration();

  Future<void> resume();

  Future<void> dispose();
}

/// Probes duration for local files via a short-lived, muted [ap.AudioPlayer].
///
/// `audioplayers` does not reliably expose a duration after `setSource` alone:
/// on several platforms `getDuration()` returns null and `onDurationChanged`
/// only fires once playback starts. The probe therefore starts muted playback
/// to force the platform to prepare the source, captures the first reported
/// duration, then disposes the player. Returns null for remote sources or if
/// the duration can't be read in time.
class AudioPlayersDurationProbe implements AudioDurationProbe {
  AudioPlayersDurationProbe({
    ProbeAudioPlayer Function()? playerFactory,
    Duration timeout = const Duration(seconds: 5),
  }) : _playerFactory = playerFactory ?? _defaultPlayerFactory,
       _timeout = timeout;

  static ProbeAudioPlayer _defaultPlayerFactory() => _RealProbeAudioPlayer();

  final ProbeAudioPlayer Function() _playerFactory;
  final Duration _timeout;

  @override
  Future<Duration?> durationOf(AudioSource source) async {
    if (source.kind != AudioSourceKind.localFile) return null;

    final player = _playerFactory();
    StreamSubscription<Duration>? sub;
    try {
      final completer = Completer<Duration?>();
      sub = player.onDurationChanged.listen((d) {
        if (d > Duration.zero && !completer.isCompleted) completer.complete(d);
      });

      await player.configureForSilentProbe();
      await player.setSourceDeviceFile(source.reference);
      // Muted playback forces the platform to prepare the source so its
      // duration becomes available; the player is disposed as soon as we read
      // it, so nothing audible is produced.
      await player.resume();

      final immediate = await player.getDuration();
      if (immediate != null &&
          immediate > Duration.zero &&
          !completer.isCompleted) {
        completer.complete(immediate);
      }

      return await completer.future.timeout(_timeout, onTimeout: () => null);
    } catch (error, stackTrace) {
      // A failed probe must not block adding the track; the UI simply omits the
      // duration. Log the real cause in debug so the failure isn't invisible.
      if (kDebugMode) {
        debugPrint(
          'Failed to probe duration for ${source.displayName}: '
          '$error\n$stackTrace',
        );
      }
      return null;
    } finally {
      await sub?.cancel();
      await player.dispose();
    }
  }
}

class _RealProbeAudioPlayer implements ProbeAudioPlayer {
  final ap.AudioPlayer _player = ap.AudioPlayer();

  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;

  @override
  Future<void> configureForSilentProbe() async {
    await _player.setReleaseMode(ap.ReleaseMode.stop);
    await _player.setVolume(0);
  }

  @override
  Future<void> setSourceDeviceFile(String path) =>
      _player.setSourceDeviceFile(path);

  @override
  Future<Duration?> getDuration() => _player.getDuration();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> dispose() => _player.dispose();
}
