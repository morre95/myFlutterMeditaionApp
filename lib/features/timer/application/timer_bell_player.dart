import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../../player/application/playback_source_resolver.dart';

/// Plays the sound that marks the end of a timed session.
abstract interface class BellPlayer {
  Future<void> playAsset(String assetPath);

  Future<void> playMedia(PlayableMedia media);

  Future<void> stop();

  FutureOr<void> dispose();
}

/// Optional completion boundary; starting playback must not hold the stop queue.
abstract interface class BellPlaybackLifecycle {
  Future<void> get playbackFinished;
}

class TimerBellPlayer implements BellPlayer, BellPlaybackLifecycle {
  TimerBellPlayer({AudioPlayer? player, bool manageAudioFocus = true})
    : _player = player ?? AudioPlayer() {
    _ready = Future.wait([
      _player.setReleaseMode(ReleaseMode.stop),
      if (!manageAudioFocus)
        _player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              audioFocus: AndroidAudioFocus.none,
            ),
          ),
        ),
    ]);
    _completion = _player.onPlayerComplete.listen(
      (_) => _finish(),
      onError: (Object error, StackTrace stack) => _finish(error, stack),
    );
  }

  final AudioPlayer _player;
  late final Future<void> _ready;
  late final StreamSubscription<void> _completion;
  Completer<void>? _finished;

  @override
  Future<void> get playbackFinished =>
      _finished?.future ?? Future<void>.value();

  void _finish([Object? error, StackTrace? stack]) {
    final finished = _finished;
    if (finished == null || finished.isCompleted) return;
    if (error == null) {
      finished.complete();
    } else {
      finished.completeError(error, stack);
    }
  }

  Future<void> _play(Source source) async {
    await _ready;
    await _player.stop();
    _finish();
    _finished = Completer<void>();
    // A native error can arrive before the caller has awaited playbackFinished.
    unawaited(_finished!.future.catchError((Object _) {}));
    try {
      await _player.play(source);
    } catch (error, stack) {
      _finish(error, stack);
      rethrow;
    }
  }

  @override
  Future<void> playAsset(String assetPath) async {
    await _play(AssetSource(assetPath));
  }

  /// Plays a custom bell that has already been resolved to a playable locator.
  @override
  Future<void> playMedia(PlayableMedia media) async {
    final source = switch (media.kind) {
      PlayableMediaKind.file => DeviceFileSource(media.locator),
      PlayableMediaKind.url => UrlSource(media.locator),
    };
    await _play(source);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _finish();
  }

  @override
  Future<void> dispose() async {
    await _completion.cancel();
    await _player.dispose();
    _finish();
  }
}
