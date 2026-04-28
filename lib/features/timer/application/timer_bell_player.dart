import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class TimerBellPlayer {
  TimerBellPlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    unawaited(_player.setReleaseMode(ReleaseMode.stop));
  }

  final AudioPlayer _player;

  Future<void> playAsset(String assetPath) async {
    await _player.stop();
    await _player.play(AssetSource(assetPath));
  }

  void dispose() {
    _player.dispose();
  }
}
