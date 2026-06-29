import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../history/application/history_controller.dart';
import '../../history/domain/meditation_session.dart';
import '../../player/application/playback_source_resolver.dart';
import '../domain/bell_selection.dart';
import '../domain/timer_settings.dart';
import '../infrastructure/shared_preferences_timer_settings_repository.dart';
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
  }) : _bellPlayer = bellPlayer ?? TimerBellPlayer(),
       _repository = repository,
       _sourceResolver = sourceResolver ?? const LocalPlaybackSourceResolver(),
       _history = history,
       _wakeLock = wakeLock ?? const WakelockPlusWakeLock() {
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
  final BellPlayer _bellPlayer;
  final TimerSettingsRepository? _repository;
  final PlaybackSourceResolver _sourceResolver;
  final HistoryController? _history;
  final WakeLock _wakeLock;
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
  Future<void> previewBell(BellSelection bell) => _playBell(bell);

  void _persistSettings() {
    final repository = _repository;
    if (repository == null) return;
    unawaited(repository.save(_state.settings));
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
    _setWakeLock(true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void pause() {
    if (!_state.isRunning) return;
    _timer?.cancel();
    _setWakeLock(false);
    _setState(_state.copyWith(status: TimerSessionStatus.paused));
  }

  void reset() {
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
    final next = _state.remaining - const Duration(seconds: 1);
    if (next <= Duration.zero) {
      _timer?.cancel();
      _complete();
      return;
    }
    _setState(_state.copyWith(remaining: next));
  }

  Future<void> _complete() async {
    _setWakeLock(false);
    _setState(
      _state.copyWith(
        remaining: Duration.zero,
        status: TimerSessionStatus.completed,
        clearError: true,
      ),
    );
    // Record the session independently of the bell so a playback error never
    // discards a completed session.
    unawaited(
      _history?.record(_state.settings.duration, mode: SessionMode.timer),
    );
    await _playBell(_state.settings.bell);
  }

  /// Plays a bell selection, surfacing a playback failure as an error message
  /// in state. Shared by end-of-session playback and dropdown previews.
  Future<void> _playBell(BellSelection bell) async {
    try {
      if (bell.isCustom) {
        final media = await _sourceResolver.resolve(bell.source!);
        await _bellPlayer.playMedia(media);
        return;
      }

      final builtIn = _builtInBellFor(bell.name);
      if (builtIn == null) {
        _setState(
          _state.copyWith(
            status: TimerSessionStatus.error,
            errorMessage: 'Selected bell is unavailable.',
          ),
        );
        return;
      }
      await _bellPlayer.playAsset(builtIn.assetPath);
    } catch (_) {
      _setState(
        _state.copyWith(
          status: TimerSessionStatus.error,
          errorMessage: 'Could not play ${bell.displayName}.',
        ),
      );
    }
  }

  BuiltInBell? _builtInBellFor(String? id) {
    for (final bell in builtInBells) {
      if (bell.id == id) return bell;
    }
    return null;
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
          debugPrint('Failed to ${enable ? 'enable' : 'disable'} wakelock: '
              '$error\n$stackTrace');
        }
      }),
    );
  }

  void _setState(TimerSessionState nextState) {
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _setWakeLock(false);
    _bellPlayer.dispose();
    super.dispose();
  }
}
