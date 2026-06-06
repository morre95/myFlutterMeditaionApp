import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../../player/application/playback_source_resolver.dart';

/// Plays the sound that marks the end of a timed session.
abstract interface class BellPlayer {
  Future<void> playAsset(String assetPath);

  Future<void> playMedia(PlayableMedia media);

  void dispose();
}

class TimerBellPlayer implements BellPlayer {
  TimerBellPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    unawaited(_player.setReleaseMode(ReleaseMode.stop));
  }

  final AudioPlayer _player;

  @override
  Future<void> playAsset(String assetPath) async {
    await _player.stop();
    await _player.play(AssetSource(assetPath));
  }

  /// Plays a custom bell that has already been resolved to a playable locator.
  @override
  Future<void> playMedia(PlayableMedia media) async {
    await _player.stop();
    final source = switch (media.kind) {
      PlayableMediaKind.file => DeviceFileSource(media.locator),
      PlayableMediaKind.url => UrlSource(media.locator),
    };
    await _player.play(source);
  }

  @override
  void dispose() {
    _player.dispose();
  }
}
