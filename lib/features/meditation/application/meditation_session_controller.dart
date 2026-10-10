import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/domain/audio_source.dart';
import '../../player/application/local_audio_playback_controller.dart';
import '../../player/application/playback_ownership_controller.dart';
import '../../player/domain/queue_entry.dart';

/// Monotonic time since an arbitrary origin; only differences are meaningful.
typedef ElapsedClock = Duration Function();

enum MeditationSessionStatus { setup, loading, running, paused, completed }

class MeditationSessionState {
  const MeditationSessionState({
    required this.status,
    required this.duration,
    this.sound,
    this.errorMessage,
  });

  final MeditationSessionStatus status;
  final Duration duration;
  final AudioSource? sound;
  final String? errorMessage;

  MeditationSessionState copyWith({
    MeditationSessionStatus? status,
    Duration? duration,
    AudioSource? sound,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MeditationSessionState(
      status: status ?? this.status,
      duration: duration ?? this.duration,
      sound: sound ?? this.sound,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Runs one timed session whose active-time countdown governs its sound.
///
/// Active time is measured with [ElapsedClock] while the sound is audibly
/// playing, so loading gaps and late interface refreshes never change it.
class MeditationSessionController extends ChangeNotifier {
  MeditationSessionController({
    required LocalAudioPlaybackController player,
    required PlaybackOwnershipController ownership,
    required ElapsedClock clock,
  }) : _player = player,
       _ownership = ownership,
       _clock = clock {
    _player.addListener(_onPlayerChanged);
  }

  static const int minMinutes = 1;
  static const int maxMinutes = 120;

  final LocalAudioPlaybackController _player;
  final PlaybackOwnershipController _ownership;
  final ElapsedClock _clock;

  MeditationSessionState _state = const MeditationSessionState(
    status: MeditationSessionStatus.setup,
    duration: Duration(minutes: 20),
  );
  Duration _activeElapsed = Duration.zero;
  Duration? _countingSince;
  Timer? _deadline;
  Timer? _refresh;
  QueueEntry? _entry;
  bool _disposed = false;

  MeditationSessionState get state => _state;

  Duration get remaining {
    final since = _countingSince;
    final active = since == null
        ? _activeElapsed
        : _activeElapsed + (_clock() - since);
    final left = _state.duration - active;
    return left > Duration.zero ? left : Duration.zero;
  }

  bool get _isSetup => _state.status == MeditationSessionStatus.setup;

  void selectSound(AudioSource sound) {
    if (!_isSetup) return;
    _setState(_state.copyWith(sound: sound));
  }

  void setDuration(Duration duration) {
    if (!_isSetup) return;
    final minutes = duration.inMinutes.clamp(minMinutes, maxMinutes);
    _setState(_state.copyWith(duration: Duration(minutes: minutes)));
  }

  Future<void> start() {
    final sound = _state.sound;
    if (sound == null || !_isSetup) {
      return Future<void>.value();
    }
    _activeElapsed = Duration.zero;
    final entry = QueueEntry(
      id: sound.id,
      source: sound,
      addedAt: DateTime.now(),
    );
    _entry = entry;
    _setState(
      _state.copyWith(
        status: MeditationSessionStatus.loading,
        clearError: true,
      ),
    );
    return _ownership.run(
      owner: this,
      deactivate: end,
      action: () => _player.play(entry),
      canRun: () => !_disposed && identical(_entry, entry),
    );
  }

  Future<void> pause() {
    if (_state.status != MeditationSessionStatus.running) {
      return Future<void>.value();
    }
    if (_countingSince != null) _stopCounting();
    _setState(_state.copyWith(status: MeditationSessionStatus.paused));
    // Stopping a repeat reload keeps a paused session silent.
    return _player.state.status == LocalPlaybackStatus.playing
        ? _player.pause()
        : _player.stop();
  }

  Future<void> resume() {
    if (_state.status != MeditationSessionStatus.paused) {
      return Future<void>.value();
    }
    _setState(_state.copyWith(status: MeditationSessionStatus.running));
    return _player.state.status == LocalPlaybackStatus.paused
        ? _player.resume()
        : _player.play(_entry!);
  }

  Future<void> end() {
    _returnToSetup();
    return _player.stop();
  }

  void _returnToSetup({String? errorMessage}) {
    if (_countingSince != null) _stopCounting();
    _activeElapsed = Duration.zero;
    _entry = null;
    _setState(
      _state.copyWith(
        status: MeditationSessionStatus.setup,
        errorMessage: errorMessage,
      ),
    );
  }

  void _onPlayerChanged() {
    final status = _state.status;
    if (status != MeditationSessionStatus.loading &&
        status != MeditationSessionStatus.running) {
      return;
    }
    switch (_player.state.status) {
      case LocalPlaybackStatus.playing when _countingSince == null:
        _setState(_state.copyWith(status: MeditationSessionStatus.running));
        _startCounting();
      case LocalPlaybackStatus.completed when _countingSince != null:
        // A sound shorter than the session repeats; the reload is not counted.
        _stopCounting();
        unawaited(_player.play(_entry!));
      case LocalPlaybackStatus.error:
        // Without audio there is no session, so nothing may count down.
        _returnToSetup(errorMessage: _player.state.errorMessage);
      default:
    }
  }

  void _startCounting() {
    _countingSince = _clock();
    _deadline = Timer(remaining, _checkDeadline);
    // Refreshes only redraw; the clock, not their count, decides remaining time.
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkDeadline();
      if (_countingSince != null) notifyListeners();
    });
  }

  void _stopCounting() {
    _deadline?.cancel();
    _refresh?.cancel();
    _activeElapsed = _state.duration - remaining;
    _countingSince = null;
  }

  void _checkDeadline() {
    if (remaining > Duration.zero) return;
    _stopCounting();
    _setState(_state.copyWith(status: MeditationSessionStatus.completed));
    unawaited(_player.stop());
  }

  void _setState(MeditationSessionState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _deadline?.cancel();
    _refresh?.cancel();
    _player.removeListener(_onPlayerChanged);
    _ownership.forget(this);
    super.dispose();
  }
}
