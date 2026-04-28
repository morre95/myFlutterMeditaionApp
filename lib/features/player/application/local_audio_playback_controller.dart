import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';

import '../domain/queue_entry.dart';

enum LocalPlaybackStatus { idle, loading, playing, paused, completed, error }

class LocalAudioPlaybackState {
  const LocalAudioPlaybackState({
    required this.status,
    this.currentEntry,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.errorMessage,
  });

  const LocalAudioPlaybackState.idle()
    : status = LocalPlaybackStatus.idle,
      currentEntry = null,
      position = Duration.zero,
      duration = Duration.zero,
      errorMessage = null;

  final LocalPlaybackStatus status;
  final QueueEntry? currentEntry;
  final Duration position;
  final Duration duration;
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
    Duration? position,
    Duration? duration,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LocalAudioPlaybackState(
      status: status ?? this.status,
      currentEntry: currentEntry ?? this.currentEntry,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class LocalAudioPlaybackController extends ChangeNotifier {
  LocalAudioPlaybackController({LocalAudioPlayer? player})
    : _player = player ?? AudioPlayersLocalPlayer() {
    _completionSubscription = _player.completedStream.listen((completed) {
      if (completed && _state.currentEntry != null) {
        _setState(
          _state.copyWith(
            status: LocalPlaybackStatus.completed,
            position: _state.duration > Duration.zero
                ? _state.duration
                : _state.position,
          ),
        );
      }
    });
    _positionSubscription = _player.positionStream.listen((position) {
      _setState(_state.copyWith(position: _clampPosition(position)));
    });
    _durationSubscription = _player.durationStream.listen((duration) {
      _setState(
        _state.copyWith(
          duration: duration,
          position: _clampPosition(_state.position, duration: duration),
        ),
      );
    });
  }

  final LocalAudioPlayer _player;
  late final StreamSubscription<bool> _completionSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;

  LocalAudioPlaybackState _state = const LocalAudioPlaybackState.idle();

  LocalAudioPlaybackState get state => _state;

  Future<void> play(QueueEntry entry) async {
    _setState(
      LocalAudioPlaybackState(
        status: LocalPlaybackStatus.loading,
        currentEntry: entry,
        position: Duration.zero,
        duration: Duration.zero,
      ),
    );

    try {
      await _player.load(entry.source.reference);
      await _player.play();
      _setState(
        LocalAudioPlaybackState(
          status: LocalPlaybackStatus.playing,
          currentEntry: entry,
          position: _state.position,
          duration: _state.duration,
        ),
      );
    } catch (_) {
      _setState(
        LocalAudioPlaybackState(
          status: LocalPlaybackStatus.error,
          currentEntry: entry,
          position: _state.position,
          duration: _state.duration,
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
        position: _state.position,
        duration: _state.duration,
      ),
    );
  }

  Future<void> resume() async {
    final entry = _state.currentEntry;
    if (entry == null || _state.status != LocalPlaybackStatus.paused) {
      return;
    }

    await _player.play();
    _setState(_state.copyWith(status: LocalPlaybackStatus.playing));
  }

  Future<void> seek(Duration position) async {
    final entry = _state.currentEntry;
    if (entry == null || _state.duration <= Duration.zero) return;

    final target = _clampPosition(position);
    await _player.seek(target);
    _setState(_state.copyWith(position: target));
  }

  Future<void> stop() async {
    await _player.stop();
    _setState(const LocalAudioPlaybackState.idle());
  }

  Duration _clampPosition(Duration position, {Duration? duration}) {
    final total = duration ?? _state.duration;
    if (position < Duration.zero) return Duration.zero;
    if (total > Duration.zero && position > total) return total;
    return position;
  }

  void _setState(LocalAudioPlaybackState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _completionSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _player.dispose();
    super.dispose();
  }
}

abstract class LocalAudioPlayer {
  Stream<bool> get completedStream;

  Stream<Duration> get positionStream;

  Stream<Duration> get durationStream;

  Future<void> load(String path);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> stop();

  void dispose();
}

class AudioPlayersLocalPlayer implements LocalAudioPlayer {
  AudioPlayersLocalPlayer({ap.AudioPlayer? player})
    : _player = player ?? ap.AudioPlayer() {
    unawaited(_player.setReleaseMode(ap.ReleaseMode.stop));
  }

  final ap.AudioPlayer _player;

  @override
  Stream<bool> get completedStream => _player.onPlayerComplete.map((_) => true);

  @override
  Stream<Duration> get positionStream => _player.onPositionChanged;

  @override
  Stream<Duration> get durationStream => _player.onDurationChanged;

  @override
  Future<void> load(String path) async {
    await _player.setSource(ap.DeviceFileSource(path));
  }

  @override
  Future<void> play() async {
    await _player.resume();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
  }
}
