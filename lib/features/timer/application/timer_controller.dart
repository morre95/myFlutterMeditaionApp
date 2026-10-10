import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../history/application/history_controller.dart';
import '../../history/domain/meditation_session.dart';
import '../../player/application/playback_source_resolver.dart';
import '../../player/application/playback_ownership_controller.dart';
import '../domain/bell_selection.dart';
import '../domain/timer_settings.dart';
import '../infrastructure/shared_preferences_timer_settings_repository.dart';
import 'bell_ringer.dart';
import 'timer_bell_player.dart';
import 'wake_lock.dart';

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
  TimerController({
    BellPlayer? bellPlayer,
    TimerSettingsRepository? repository,
    PlaybackSourceResolver? sourceResolver,
    HistoryController? history,
    WakeLock? wakeLock,
    PlaybackOwnershipController? ownership,
    Duration Function()? clock,
  }) : _bell = BellRinger(
         player: bellPlayer ?? TimerBellPlayer(),
         sourceResolver: sourceResolver ?? const LocalPlaybackSourceResolver(),
       ),
       _repository = repository,
       _history = history,
       _wakeLock = wakeLock ?? const WakelockPlusWakeLock(),
       _ownership = ownership,
       _clock = clock ?? _monotonicClock() {
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
  final BellRinger _bell;
  final TimerSettingsRepository? _repository;
  final HistoryController? _history;
  final Duration Function() _clock;
  static Duration Function() _monotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  String? _sessionId;
  Duration _activeElapsed = Duration.zero;
  Duration? _countingSince;
  Duration _planned = Duration.zero;

  Duration get _elapsed =>
      _activeElapsed +
      (_countingSince == null ? Duration.zero : _clock() - _countingSince!);
  void _stopCounting() {
    _activeElapsed = _elapsed;
    _countingSince = null;
  }

  void _recordOutcome() {
    final id = _sessionId;
    if (id == null) return;
    _stopCounting();
    _sessionId = null;
    final completed = _activeElapsed >= _planned;
    final actual = completed ? _planned : _activeElapsed;
    unawaited(
      _history
          ?.record(
            _planned,
            id: id,
            actualDuration: actual,
            mode: SessionMode.timer,
            outcome: completed
                ? SessionOutcome.completed
                : SessionOutcome.endedEarly,
          )
          .catchError((Object error) {
            debugPrint('Could not save timer history (${error.runtimeType}).');
          }),
    );
  }

  final WakeLock _wakeLock;
  final PlaybackOwnershipController? _ownership;
  bool _disposed = false;
  Future<void>? _disposal;
  int _bellGeneration = 0;
  int _bellRequestGeneration = 0;
  Timer? _timer;
  late TimerSessionState _state;

  /// Restores the last-used duration and bell. Call once at startup.
  Future<void> load() async {
    final repository = _repository;
    if (repository == null || _state.status != TimerSessionStatus.idle) return;
    final saved = await repository.load();
    if (saved == null) return;
    final sanitizedMinutes = saved.duration.inMinutes.clamp(
      _minDurationMinutes,
      _maxDurationMinutes,
    );
    final duration = Duration(minutes: sanitizedMinutes);
    _setState(
      _state.copyWith(
        settings: TimerSettings(duration: duration, bell: saved.bell),
        remaining: duration,
      ),
    );
  }

  TimerSessionState get state => _state;

  Duration get selectedDuration => _state.settings.duration;

  BellSelection get selectedBell => _state.settings.bell;

  void setDuration(Duration duration) {
    if (_state.isRunning || _state.isPaused) return;
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
    _persistSettings();
  }

  void setBell(BellSelection bell) {
    _setState(
      _state.copyWith(
        settings: _state.settings.copyWith(bell: bell),
        clearError: true,
      ),
    );
    _persistSettings();
  }

  /// Plays [bell] so the user can hear their selection before a session ends.
  Future<void> previewBell(BellSelection bell) {
    final request = ++_bellRequestGeneration;
    return _withOwnership(
      () => _playBell(bell),
      canRun: () => request == _bellRequestGeneration,
    );
  }

  void _persistSettings() {
    final repository = _repository;
    if (repository == null) return;
    unawaited(repository.save(_state.settings));
  }

  Future<void> start() => _withOwnership(() async => _start());

  void _start() {
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
    if (_sessionId == null) {
      _sessionId = newSessionId();
      _activeElapsed = Duration.zero;
      _planned = _state.settings.duration;
    }
    _countingSince = _clock();
    final session = _sessionId;
    _setState(
      _state.copyWith(status: TimerSessionStatus.running, clearError: true),
    );
    if (!_state.isRunning || _sessionId != session) return;
    _setWakeLock(true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void pause() {
    if (!_state.isRunning) return;
    _timer?.cancel();
    _stopCounting();
    _setWakeLock(false);
    _setState(
      _state.copyWith(
        status: TimerSessionStatus.paused,
        remaining:
            _planned - (_activeElapsed > _planned ? _planned : _activeElapsed),
      ),
    );
  }

  void reset() {
    _bellRequestGeneration++;
    _resetSession();
  }

  void _resetSession() {
    _recordOutcome();
    _bellGeneration++;
    _timer?.cancel();
    _setWakeLock(false);
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
    if (!_state.isRunning || _sessionId == null) return;
    final next = _planned - _elapsed;
    if (next <= Duration.zero) {
      _timer?.cancel();
      _complete();
      return;
    }
    _setState(_state.copyWith(remaining: next));
  }

  Future<void> _complete() async {
    if (_sessionId == null) return;
    _recordOutcome();
    _setWakeLock(false);
    _setState(
      _state.copyWith(
        remaining: Duration.zero,
        status: TimerSessionStatus.completed,
        clearError: true,
      ),
    );
    final generation = _bellGeneration;
    await _withOwnership(
      () => _playBell(_state.settings.bell),
      canRun: () => generation == _bellGeneration && _state.isCompleted,
    );
  }

  /// Plays a bell selection, surfacing a playback failure as an error message
  /// in state. Shared by end-of-session playback and dropdown previews.
  Future<void> _playBell(BellSelection bell) async {
    final generation = ++_bellGeneration;
    try {
      await _bell.ring(
        bell,
        canRun: () => !_disposed && generation == _bellGeneration,
      );
    } on UnavailableBellException {
      _setState(
        _state.copyWith(
          status: TimerSessionStatus.error,
          errorMessage: 'Selected bell is unavailable.',
        ),
      );
    } catch (_) {
      if (_disposed || generation != _bellGeneration) return;
      _setState(
        _state.copyWith(
          status: TimerSessionStatus.error,
          errorMessage: 'Could not play ${bell.displayName}.',
        ),
      );
    }
  }

  /// Toggles the screen wakelock for the session lifecycle. Best-effort: a
  /// wakelock failure must never interrupt or fail the meditation timer, so the
  /// error is logged in debug builds and otherwise ignored.
  void _setWakeLock(bool enable) {
    unawaited(
      (enable ? _wakeLock.enable() : _wakeLock.disable()).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        if (kDebugMode) {
          debugPrint(
            'Failed to ${enable ? 'enable' : 'disable'} wakelock: '
            '$error\n$stackTrace',
          );
        }
      }),
    );
  }

  Future<void> _withOwnership(
    Future<void> Function() action, {
    bool Function()? canRun,
  }) {
    bool isCurrent() => !_disposed && (canRun?.call() ?? true);
    final ownership = _ownership;
    if (ownership == null) {
      return isCurrent() ? action() : Future<void>.value();
    }
    return ownership.run(
      owner: this,
      deactivate: () async {
        if (_disposed) {
          await _disposal;
          return;
        }
        _resetSession();
        await _bell.stop();
      },
      action: action,
      canRun: isCurrent,
    );
  }

  void _setState(TimerSessionState nextState) {
    if (_disposed) return;
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _bellGeneration++;
    _timer?.cancel();
    _setWakeLock(false);
    _disposal = _bell.dispose();
    unawaited(
      _disposal!.then<void>(
        (_) => _ownership?.forget(this),
        onError: (Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            debugPrint(
              'Timer bell disposal failed (${error.runtimeType}); '
              'playback ownership retained.',
            );
          }
        },
      ),
    );
    super.dispose();
  }
}
