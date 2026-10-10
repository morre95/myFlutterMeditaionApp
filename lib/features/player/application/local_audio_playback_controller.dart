import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart';

import '../domain/queue_entry.dart';
import 'playback_source_resolver.dart';
import 'audio_command_queue.dart';

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
  LocalAudioPlaybackController({
    LocalAudioPlayer? player,
    PlaybackSourceResolver? resolver,
  }) : _player = player ?? AudioPlayersLocalPlayer(),
       _resolver = resolver ?? const LocalPlaybackSourceResolver() {
    _completionSubscription = _player.completedStream.listen((completed) {
      if (completed &&
          _state.currentEntry != null &&
          (_state.status == LocalPlaybackStatus.playing ||
              _state.status == LocalPlaybackStatus.paused)) {
        _setState(
          _state.copyWith(
            status: LocalPlaybackStatus.completed,
            position: _state.duration > Duration.zero
                ? _state.duration
                : _state.position,
          ),
        );
      }
    }, onError: _onNativeError);
    _positionSubscription = _player.positionStream.listen((position) {
      if (_state.status == LocalPlaybackStatus.playing ||
          _state.status == LocalPlaybackStatus.paused) {
        _setState(_state.copyWith(position: _clampPosition(position)));
      }
    }, onError: _onNativeError);
    _durationSubscription = _player.durationStream.listen((duration) {
      _setState(
        _state.copyWith(
          duration: duration,
          position: _clampPosition(_state.position, duration: duration),
        ),
      );
    }, onError: _onNativeError);
  }

  void _onNativeError(Object error) {
    final entry = _state.currentEntry;
    if (entry == null || _state.status == LocalPlaybackStatus.error) return;
    _playbackGeneration++;
    _setState(
      _state.copyWith(
        status: LocalPlaybackStatus.error,
        errorMessage: 'Could not play ${entry.source.displayName}.',
      ),
    );
  }

  final LocalAudioPlayer _player;
  final PlaybackSourceResolver _resolver;
  late final StreamSubscription<bool> _completionSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration> _durationSubscription;

  LocalAudioPlaybackState _state = const LocalAudioPlaybackState.idle();

  bool _disposed = false;
  final _playerCommands = AudioCommandQueue();
  Future<void>? _disposal;
  int _playbackGeneration = 0;

  LocalAudioPlaybackState get state => _state;

  Future<void> play(
    QueueEntry entry, {
    Duration position = Duration.zero,
  }) async {
    if (_disposed) return;
    final generation = ++_playbackGeneration;
    _setState(
      LocalAudioPlaybackState(
        status: LocalPlaybackStatus.loading,
        currentEntry: entry,
        position: Duration.zero,
        duration: Duration.zero,
      ),
    );

    try {
      final media = await _resolver.resolve(entry.source);
      if (!_isCurrent(generation)) {
        return;
      }
      await _playerCommands.run(
        () => _player.load(media),
        canRun: () => _isCurrent(generation),
      );
      if (!_isCurrent(generation)) {
        return;
      }
      if (position > Duration.zero) {
        await _playerCommands.run(
          () => _player.seek(position),
          canRun: () => _isCurrent(generation),
        );
      }
      await _playerCommands.run(
        _player.play,
        canRun: () => _isCurrent(generation),
      );
      if (!_isCurrent(generation)) {
        return;
      }
      _setState(
        LocalAudioPlaybackState(
          status: LocalPlaybackStatus.playing,
          currentEntry: entry,
          position: position,
          duration: _state.duration,
        ),
      );
    } catch (_) {
      if (!_isCurrent(generation)) {
        return;
      }
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

    final generation = _playbackGeneration;
    await _playerCommands.run(
      _player.pause,
      canRun: () =>
          _isCurrent(generation) &&
          _state.status == LocalPlaybackStatus.playing,
    );
    if (!_isCurrent(generation) ||
        _state.status != LocalPlaybackStatus.playing) {
      return;
    }
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

    final generation = _playbackGeneration;
    await _playerCommands.run(
      _player.play,
      canRun: () =>
          _isCurrent(generation) && _state.status == LocalPlaybackStatus.paused,
    );
    if (!_isCurrent(generation) ||
        _state.status != LocalPlaybackStatus.paused) {
      return;
    }
    _setState(_state.copyWith(status: LocalPlaybackStatus.playing));
  }

  Future<void> seek(Duration position) async {
    final entry = _state.currentEntry;
    if (entry == null || _state.duration <= Duration.zero) return;

    final target = _clampPosition(position);
    final generation = _playbackGeneration;
    await _playerCommands.run(
      () => _player.seek(target),
      canRun: () => _isCurrent(generation),
    );
    if (!_isCurrent(generation)) {
      return;
    }
    _setState(_state.copyWith(position: target));
  }

  /// Sets the native volume, from 0 (silent) to 1 (full); it persists across
  /// loads.
  Future<void> setVolume(double volume) =>
      _playerCommands.run(() => _player.setVolume(volume));

  Future<void> stop() async {
    if (_disposed) {
      await _disposal;
      return;
    }
    _playbackGeneration++;
    _setState(const LocalAudioPlaybackState.idle());
    await _playerCommands.run(_player.stop);
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _playbackGeneration;

  Duration _clampPosition(Duration position, {Duration? duration}) {
    final total = duration ?? _state.duration;
    if (position < Duration.zero) return Duration.zero;
    if (total > Duration.zero && position > total) return total;
    return position;
  }

  void _setState(LocalAudioPlaybackState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackGeneration++;
    _completionSubscription.cancel();
    _positionSubscription.cancel();
    _durationSubscription.cancel();
    _disposal = _playerCommands.disposePlayer(
      stop: _player.stop,
      dispose: _player.dispose,
    );
    unawaited(
      _disposal!.catchError((Object error, StackTrace stackTrace) {
        if (kDebugMode) {
          debugPrint(
            'Music player disposal failed (${error.runtimeType}); '
            'native silence could not be confirmed.',
          );
        }
      }),
    );
    super.dispose();
  }
}

abstract class LocalAudioPlayer {
  Stream<bool> get completedStream;

  Stream<Duration> get positionStream;

  Stream<Duration> get durationStream;

  Future<void> load(PlayableMedia media);

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> stop();

  Future<void> setVolume(double volume);

  FutureOr<void> dispose();
}

class AudioPlayersLocalPlayer implements LocalAudioPlayer {
  AudioPlayersLocalPlayer({ap.AudioPlayer? player})
    : _player = player ?? ap.AudioPlayer() {
    _player.positionUpdater = ap.TimerPositionUpdater(
      interval: const Duration(milliseconds: 200),
      getPosition: _player.getCurrentPosition,
    );
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
  Future<void> load(PlayableMedia media) async {
    final source = switch (media.kind) {
      PlayableMediaKind.file => ap.DeviceFileSource(media.locator),
      PlayableMediaKind.url => ap.UrlSource(media.locator),
    };
    await _player.setSource(source);
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
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}
