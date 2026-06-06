import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;

import '../../../shared/domain/audio_source.dart';

/// Reads the duration of an audio source without playing it. Abstracted so the
/// UI can be tested without the audio plugin.
abstract interface class AudioDurationProbe {
  Future<Duration?> durationOf(AudioSource source);
}

/// Probes duration for local files via a short-lived [ap.AudioPlayer]. Returns
/// null for remote sources or if the duration can't be read in time.
class AudioPlayersDurationProbe implements AudioDurationProbe {
  const AudioPlayersDurationProbe();

  static const _timeout = Duration(seconds: 3);

  @override
  Future<Duration?> durationOf(AudioSource source) async {
    if (source.kind != AudioSourceKind.localFile) return null;

    final player = ap.AudioPlayer();
    StreamSubscription<Duration>? sub;
    try {
      final completer = Completer<Duration?>();
      sub = player.onDurationChanged.listen((d) {
        if (!completer.isCompleted) completer.complete(d);
      });
      await player.setReleaseMode(ap.ReleaseMode.stop);
      await player.setSourceDeviceFile(source.reference);

      final immediate = await player.getDuration();
      if (immediate != null && !completer.isCompleted) {
        completer.complete(immediate);
      }
      return await completer.future.timeout(_timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      await sub?.cancel();
      await player.dispose();
    }
  }
}
