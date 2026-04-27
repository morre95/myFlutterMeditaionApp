import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

import '../domain/queue_entry.dart';

enum LocalPlaybackStatus { idle, loading, playing, paused, completed, error }

class LocalAudioPlaybackState {
  const LocalAudioPlaybackState({
    required this.status,
    this.currentEntry,
    this.errorMessage,
  });

  const LocalAudioPlaybackState.idle()
    : status = LocalPlaybackStatus.idle,
      currentEntry = null,
      errorMessage = null;

  final LocalPlaybackStatus status;
  final QueueEntry? currentEntry;
  final String? errorMessage;

  bool get canPause => status == LocalPlaybackStatus.playing;

  bool get canStop =>
      status == LocalPlaybackStatus.playing ||
      status == LocalPlaybackStatus.paused ||
      status == LocalPlaybackStatus.completed ||
      status == LocalPlaybackStatus.error;

  LocalAudioPlaybackState copyWith({
    LocalPlaybackStatus? status,
    QueueEntry? currentEntry,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LocalAudioPlaybackState(
      status: status ?? this.status,
      currentEntry: currentEntry ?? this.currentEntry,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class LocalAudioPlaybackController extends ChangeNotifier {
  LocalAudioPlaybackController({LocalAudioPlayer? player})
    : _player = player ?? JustAudioLocalPlayer() {
    _completionSubscription = _player.completedStream.listen((completed) {
      if (completed && _state.currentEntry != null) {
        _setState(_state.copyWith(status: LocalPlaybackStatus.completed));
      }
    });
  }

  final LocalAudioPlayer _player;
  late final StreamSubscription<bool> _completionSubscription;

  LocalAudioPlaybackState _state = const LocalAudioPlaybackState.idle();

  LocalAudioPlaybackState get state => _state;

  Future<void> play(QueueEntry entry) async {
    _setState(
      LocalAudioPlaybackState(
        status: LocalPlaybackStatus.loading,
        currentEntry: entry,
      ),
    );

    try {
      await _player.load(entry.source.reference);
      await _player.play();
      _setState(
        LocalAudioPlaybackState(
          status: LocalPlaybackStatus.playing,
          currentEntry: entry,
        ),
      );
    } catch (_) {
      _setState(
        LocalAudioPlaybackState(
          status: LocalPlaybackStatus.error,
          currentEntry: entry,
          errorMessage: 'Could not play ${entry.source.displayName}.',
        ),
      );
    }
  }

  Future<void> pause() async {
    final entry = _state.currentEntry;
    if (entry == null || _state.status != LocalPlaybackStatus.playing) {
      return;
    }

    await _player.pause();
    _setState(
      LocalAudioPlaybackState(
        status: LocalPlaybackStatus.paused,
        currentEntry: entry,
      ),
    );
  }

  Future<void> stop() async {
    await _player.stop();
    _setState(const LocalAudioPlaybackState.idle());
  }

  void _setState(LocalAudioPlaybackState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _completionSubscription.cancel();
    _player.dispose();
    super.dispose();
  }
}

abstract class LocalAudioPlayer {
  Stream<bool> get completedStream;

  Future<void> load(String path);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  void dispose();
}

class JustAudioLocalPlayer implements LocalAudioPlayer {
  JustAudioLocalPlayer({just_audio.AudioPlayer? player})
    : _player = player ?? just_audio.AudioPlayer();

  final just_audio.AudioPlayer _player;

  @override
  Stream<bool> get completedStream => _player.playerStateStream.map(
    (state) => state.processingState == just_audio.ProcessingState.completed,
  );

  @override
  Future<void> load(String path) {
    return _player.setUrl(Uri.file(path).toString()).then((_) {});
  }

  @override
  Future<void> play() {
    return _player.play();
  }

  @override
  Future<void> pause() {
    return _player.pause();
  }

  @override
  Future<void> stop() {
    return _player.stop();
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
  }
}
