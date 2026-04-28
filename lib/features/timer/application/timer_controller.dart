import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/bell_selection.dart';
import '../domain/timer_settings.dart';
import 'timer_bell_player.dart';

enum TimerSessionStatus { idle, running, paused, completed, error }

class TimerSessionState {
  const TimerSessionState({
    required this.settings,
    required this.remaining,
    required this.status,
    this.errorMessage,
  });

  factory TimerSessionState.initial({required TimerSettings settings}) {
    return TimerSessionState(
      settings: settings,
      remaining: settings.duration,
      status: TimerSessionStatus.idle,
    );
  }

  final TimerSettings settings;
  final Duration remaining;
  final TimerSessionStatus status;
  final String? errorMessage;

  bool get isRunning => status == TimerSessionStatus.running;

  bool get isPaused => status == TimerSessionStatus.paused;

  bool get isCompleted => status == TimerSessionStatus.completed;

  double get progress {
    final totalSeconds = settings.duration.inSeconds;
    if (totalSeconds <= 0) return 0;
    final remainingSeconds = remaining.inSeconds.clamp(0, totalSeconds);
    return (totalSeconds - remainingSeconds) / totalSeconds;
  }

  TimerSessionState copyWith({
    TimerSettings? settings,
    Duration? remaining,
    TimerSessionStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TimerSessionState(
      settings: settings ?? this.settings,
      remaining: remaining ?? this.remaining,
      status: status ?? this.status,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class TimerController extends ChangeNotifier {
  TimerController({TimerBellPlayer? bellPlayer})
    : _bellPlayer = bellPlayer ?? TimerBellPlayer() {
    final defaultBell = builtInBells.first;
    _state = TimerSessionState.initial(
      settings: TimerSettings(
        duration: _defaultDuration,
        bell: defaultBell.toSelection(),
      ),
    );
  }

  static const Duration _defaultDuration = Duration(minutes: 10);
  static const int _minDurationMinutes = 1;
  static const int _maxDurationMinutes = 120;
  final TimerBellPlayer _bellPlayer;
  Timer? _timer;
  late TimerSessionState _state;

  TimerSessionState get state => _state;

  Duration get selectedDuration => _state.settings.duration;

  BellSelection get selectedBell => _state.settings.bell;

  void setDuration(Duration duration) {
    if (_state.isRunning) return;
    final sanitizedMinutes = duration.inMinutes.clamp(
      _minDurationMinutes,
      _maxDurationMinutes,
    );
    final nextDuration = Duration(minutes: sanitizedMinutes);
    _setState(
      _state.copyWith(
        settings: _state.settings.copyWith(duration: nextDuration),
        remaining: nextDuration,
        status: TimerSessionStatus.idle,
        clearError: true,
      ),
    );
  }

  void setBell(BellSelection bell) {
    _setState(
      _state.copyWith(
        settings: _state.settings.copyWith(bell: bell),
        clearError: true,
      ),
    );
  }

  void start() {
    if (_state.isRunning) return;
    _timer?.cancel();
    if (_state.remaining <= Duration.zero || _state.isCompleted) {
      _setState(
        _state.copyWith(
          remaining: _state.settings.duration,
          status: TimerSessionStatus.idle,
          clearError: true,
        ),
      );
    }
    _setState(
      _state.copyWith(status: TimerSessionStatus.running, clearError: true),
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void pause() {
    if (!_state.isRunning) return;
    _timer?.cancel();
    _setState(_state.copyWith(status: TimerSessionStatus.paused));
  }

  void reset() {
    _timer?.cancel();
    final duration = _state.settings.duration;
    _setState(
      _state.copyWith(
        remaining: duration,
        status: TimerSessionStatus.idle,
        clearError: true,
      ),
    );
  }

  void _onTick() {
    final next = _state.remaining - const Duration(seconds: 1);
    if (next <= Duration.zero) {
      _timer?.cancel();
      _complete();
      return;
    }
    _setState(_state.copyWith(remaining: next));
  }

  Future<void> _complete() async {
    _setState(
      _state.copyWith(
        remaining: Duration.zero,
        status: TimerSessionStatus.completed,
        clearError: true,
      ),
    );
    final selected = _state.settings.bell;
    BuiltInBell? builtIn;
    for (final bell in builtInBells) {
      if (bell.id == selected.name) {
        builtIn = bell;
        break;
      }
    }
    if (builtIn == null) {
      _setState(
        _state.copyWith(
          status: TimerSessionStatus.error,
          errorMessage: 'Selected bell is unavailable.',
        ),
      );
      return;
    }
    try {
      await _bellPlayer.playAsset(builtIn.assetPath);
    } catch (_) {
      _setState(
        _state.copyWith(
          status: TimerSessionStatus.error,
          errorMessage: 'Could not play ${builtIn.label}.',
        ),
      );
    }
  }

  void _setState(TimerSessionState nextState) {
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bellPlayer.dispose();
    super.dispose();
  }
}
