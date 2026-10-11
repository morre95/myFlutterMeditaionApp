import 'dart:async';

import '../../history/application/history_controller.dart';
import '../../history/domain/meditation_session.dart';

import 'package:flutter/foundation.dart';

import '../../../shared/domain/audio_source.dart';
import '../../player/application/local_audio_playback_controller.dart';
import '../../player/application/playback_ownership_controller.dart';
import '../../player/domain/queue_entry.dart';
import '../../settings/application/app_settings_controller.dart';
import '../../timer/application/bell_ringer.dart';
import '../../timer/domain/bell_selection.dart';
import '../domain/meditation_checkpoint.dart';
import '../domain/meditation_settings.dart';
import '../infrastructure/shared_preferences_meditation_checkpoint_repository.dart';
import '../infrastructure/shared_preferences_meditation_settings_repository.dart';

/// Monotonic time since an arbitrary origin; only differences are meaningful.
typedef ElapsedClock = Duration Function();

enum MeditationSessionStatus { setup, loading, running, paused, completed }

class MeditationSessionState {
  const MeditationSessionState({
    required this.status,
    required this.duration,
    required this.bell,
    required this.isBellEnabled,
    this.sound,
    this.errorMessage,
  });

  final MeditationSessionStatus status;
  final Duration duration;

  /// The remembered bell choice, which Settings may since have removed or
  /// disabled; [MeditationSessionController.bell] is the one that rings.
  final BellSelection bell;
  final bool isBellEnabled;
  final AudioSource? sound;
  final String? errorMessage;

  MeditationSessionState copyWith({
    MeditationSessionStatus? status,
    Duration? duration,
    BellSelection? bell,
    bool? isBellEnabled,
    AudioSource? sound,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MeditationSessionState(
      status: status ?? this.status,
      duration: duration ?? this.duration,
      bell: bell ?? this.bell,
      isBellEnabled: isBellEnabled ?? this.isBellEnabled,
      sound: sound ?? this.sound,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Runs one timed session whose active-time countdown governs its sound.
///
/// Local active time uses [ElapsedClock]. Streamed active time follows advancing
/// media positions, so buffering and loading cannot consume meditation time.
class MeditationSessionController extends ChangeNotifier {
  MeditationSessionController({
    required LocalAudioPlaybackController player,
    required BellRinger bell,
    required MeditationSettingsRepository repository,
    required MeditationCheckpointRepository checkpoints,
    required PlaybackOwnershipController ownership,
    required AppSettingsController appSettings,
    required ElapsedClock clock,
    Future<bool> Function()? acquireAudioFocus,
    HistoryController? history,
  }) : _player = player,
       _bell = bell,
       _repository = repository,
       _checkpoints = checkpoints,
       _ownership = ownership,
       _appSettings = appSettings,
       _clock = clock,
       _acquireAudioFocus = acquireAudioFocus,
       _history = history {
    _player.addListener(_onPlayerChanged);
  }

  static const int minMinutes = 1;
  static const int maxMinutes = 120;

  /// Shorter play-throughs cannot loop without reloading continuously.
  static const Duration minimumPlayThrough = Duration(seconds: 1);

  /// The sound fades out over this much final active time.
  static const Duration fadeDuration = Duration(seconds: 5);
  static const Duration _fadeStep = Duration(milliseconds: 100);

  /// How often an active session's progress is made durable; termination can
  /// lose at most this much active time plus storage flush latency.
  static const Duration checkpointInterval = Duration(seconds: 5);

  final LocalAudioPlaybackController _player;
  final BellRinger _bell;
  final MeditationSettingsRepository _repository;
  final MeditationCheckpointRepository _checkpoints;
  Future<void> _checkpointWrites = Future<void>.value();
  Timer? _checkpointTimer;

  /// A restored session has nothing loaded natively until Resume.
  bool _needsReload = false;
  Duration _resumePosition = Duration.zero;
  final PlaybackOwnershipController _ownership;
  final AppSettingsController _appSettings;
  final ElapsedClock _clock;
  final Future<bool> Function()? _acquireAudioFocus;
  int _command = 0;
  int _pendingStops = 0;
  bool _stopFailed = false;
  bool get isSilencing => _pendingStops > 0 || _stopFailed;
  bool get hasSilencingError => _stopFailed;
  QueueEntry? _finishingBell;
  bool get isFinishingBell => _finishingBell != null;
  final HistoryController? _history;
  String? _historySessionId;

  MeditationSessionState _state = MeditationSessionState(
    status: MeditationSessionStatus.setup,
    duration: const Duration(minutes: 20),
    bell: builtInBells.first.toSelection(),
    isBellEnabled: true,
  );
  Duration _activeElapsed = Duration.zero;
  Duration? _countingSince;
  Timer? _deadline;
  Timer? _refresh;
  Timer? _fade;
  QueueEntry? _entry;
  Duration _playThroughStart = Duration.zero;
  Future<void>? _pendingPause;
  Future<void> _lastSave = Future<void>.value();
  bool _disposed = false;
  int _sessionId = 0;
  final int _sessionEpoch = DateTime.now().microsecondsSinceEpoch;
  String get sessionId => '$_sessionEpoch-$_sessionId';
  // audioplayers has no native buffering state. Count only reported progress,
  // and require explicit recovery after five seconds without advancing media.
  Timer? _streamWatchdog;
  Duration _streamPosition = Duration.zero;
  bool get _isStream => _state.sound?.kind == AudioSourceKind.pCloud;

  void _watchStream() {
    _streamWatchdog?.cancel();
    _streamWatchdog = Timer(const Duration(seconds: 5), () {
      if (_state.status == MeditationSessionStatus.loading ||
          _state.status == MeditationSessionStatus.running) {
        _interruptPlayback('Sound is buffering. Resume to try again.');
      }
    });
  }

  void _interruptPlayback(String? message) {
    ++_command;
    _streamWatchdog?.cancel();
    _streamWatchdog = null;
    _setState(
      _state.copyWith(
        status: MeditationSessionStatus.paused,
        errorMessage: message,
      ),
    );
    _saveCheckpoint();
    final entry = _entry;
    late final Future<void> pending;
    pending = _player
        .stop(pauseOnFailure: true)
        .catchError((Object error) {
          debugPrint(
            'Meditate recovery could not silence audio (${error.runtimeType}).',
          );
          if (!_disposed && identical(_entry, entry)) {
            _setState(
              _state.copyWith(
                status: MeditationSessionStatus.paused,
                errorMessage:
                    'Could not silence the sound. Resume to try again.',
              ),
            );
          }
        })
        .whenComplete(() {
          if (identical(_pendingPause, pending)) _pendingPause = null;
        });
    _pendingPause = pending;
  }

  void _onStreamChanged() {
    final player = _player.state;
    if (player.status == LocalPlaybackStatus.error) {
      _interruptPlayback(player.errorMessage);
      return;
    }
    if (player.status == LocalPlaybackStatus.playing && _pendingPause == null) {
      if (_streamWatchdog == null) _watchStream();
      final position = player.position;
      if (position > _streamPosition) {
        // Loading and retry seek events are excluded by the playing guard.
        _activeElapsed += position - _streamPosition;
        _streamPosition = position;
        _setState(
          _state.copyWith(
            status: MeditationSessionStatus.running,
            clearError: true,
          ),
        );
        _watchStream();
        if (remaining <= fadeDuration) _applyFade();
        _checkDeadline();
      }
    } else if (player.status == LocalPlaybackStatus.completed) {
      _streamWatchdog?.cancel();
      _streamWatchdog = null;
      if (_activeElapsed - _playThroughStart < minimumPlayThrough) {
        _interruptPlayback('Sound ended before it could be played.');
        return;
      }
      _playThroughStart = _activeElapsed;
      _streamPosition = Duration.zero;
      _setState(_state.copyWith(status: MeditationSessionStatus.loading));
      unawaited(_player.play(_entry!));
    }
  }

  MeditationSessionState get state => _state;

  /// The bell setup shows and completion rings: the remembered
  /// [MeditationSessionState.bell] while Settings still offers it, otherwise
  /// the fallback, so the two never differ.
  BellSelection get bell => _appSettings.availableBellFor(_state.bell);

  Duration get remaining {
    final since = _countingSince;
    final active = since == null
        ? _activeElapsed
        : _activeElapsed + (_clock() - since);
    final left = _state.duration - active;
    return left > Duration.zero ? left : Duration.zero;
  }

  bool get _isSetup => _state.status == MeditationSessionStatus.setup;

  /// Restores the last choices and any unfinished session, paused. Call once
  /// at startup.
  Future<void> load() async {
    final saved = await _repository.load();
    final checkpoint = await _loadCheckpoint();
    if (!_isSetup) return;
    if (saved != null) {
      _setState(
        _state.copyWith(
          sound: saved.sound,
          duration: _withinRange(saved.duration),
          bell: saved.bell,
          isBellEnabled: saved.isBellEnabled,
        ),
      );
    }
    if (checkpoint != null) _restore(checkpoint);
  }

  Future<MeditationCheckpoint?> _loadCheckpoint() async {
    final MeditationCheckpoint? checkpoint;
    try {
      checkpoint = await _checkpoints.load();
    } catch (error) {
      debugPrint(
        'Could not read unfinished meditation (${error.runtimeType}).',
      );
      _clearCheckpoint();
      return null;
    }
    if (checkpoint == null) return null;
    // Termination can land between recording a session and clearing it.
    if (await _wasRecorded(checkpoint.sessionId)) {
      _clearCheckpoint();
      return null;
    }
    return checkpoint;
  }

  Future<bool> _wasRecorded(String sessionId) async {
    try {
      return await _history?.hasRecorded(sessionId) ?? false;
    } catch (error) {
      // History deduplicates identities, so a later End cannot double count.
      debugPrint('Could not read meditation history (${error.runtimeType}).');
      return false;
    }
  }

  void _restore(MeditationCheckpoint checkpoint) {
    _sessionId++;
    _historySessionId = checkpoint.sessionId;
    _activeElapsed = checkpoint.activeDuration;
    _streamPosition = checkpoint.soundPosition;
    _resumePosition = checkpoint.soundPosition;
    final played = checkpoint.activeDuration - checkpoint.soundPosition;
    _playThroughStart = played > Duration.zero ? played : Duration.zero;
    _needsReload = true;
    _entry = QueueEntry(
      id: checkpoint.sound.id,
      source: checkpoint.sound,
      addedAt: DateTime.now(),
    );
    _checkpointTimer = Timer.periodic(checkpointInterval, (_) => _checkpoint());
    _setState(
      _state.copyWith(
        status: MeditationSessionStatus.paused,
        sound: checkpoint.sound,
        duration: checkpoint.plannedDuration,
        bell: checkpoint.bell,
        isBellEnabled: checkpoint.isBellEnabled,
        clearError: true,
      ),
    );
  }

  Duration get _soundPosition {
    if (_isStream) return _streamPosition;
    if (_needsReload) return _resumePosition;
    final player = _player.state;
    return identical(player.currentEntry, _entry)
        ? player.position
        : Duration.zero;
  }

  /// Saves progress while the session can advance; pauses save explicitly.
  void _checkpoint() {
    final status = _state.status;
    if (status == MeditationSessionStatus.loading ||
        status == MeditationSessionStatus.running) {
      _saveCheckpoint();
    }
  }

  void _saveCheckpoint() {
    final id = _historySessionId;
    final sound = _state.sound;
    if (id == null || sound == null || _entry == null) return;
    final checkpoint = MeditationCheckpoint(
      sessionId: id,
      sound: sound,
      plannedDuration: _state.duration,
      activeDuration: _state.duration - remaining,
      soundPosition: _soundPosition,
      bell: _state.bell,
      isBellEnabled: _state.isBellEnabled,
    );
    _persistCheckpoint(() => _checkpoints.save(checkpoint));
  }

  void _clearCheckpoint() => _persistCheckpoint(_checkpoints.clear);

  /// Serialized, so a slow earlier write never lands after a later one.
  void _persistCheckpoint(Future<void> Function() write) {
    _checkpointWrites = _checkpointWrites.then((_) => write()).catchError((
      Object error,
    ) {
      debugPrint('Could not save meditation progress (${error.runtimeType}).');
    });
  }

  void selectSound(AudioSource sound) =>
      _changeSetup(_state.copyWith(sound: sound));

  void setDuration(Duration duration) =>
      _changeSetup(_state.copyWith(duration: _withinRange(duration)));

  void selectBell(BellSelection bell) =>
      _changeSetup(_state.copyWith(bell: bell));

  void setBellEnabled(bool enabled) =>
      _changeSetup(_state.copyWith(isBellEnabled: enabled));

  static Duration _withinRange(Duration duration) =>
      Duration(minutes: duration.inMinutes.clamp(minMinutes, maxMinutes));

  /// Choices are locked once a session starts; each one is remembered.
  void _changeSetup(MeditationSessionState next) {
    if (!_isSetup) return;
    _setState(next);
    final settings = MeditationSettings(
      sound: next.sound,
      duration: next.duration,
      bell: next.bell,
      isBellEnabled: next.isBellEnabled,
    );
    // Concurrent saves can land out of order; chaining keeps the latest last.
    _lastSave = _lastSave.then((_) => _repository.save(settings)).catchError((
      Object error,
    ) {
      debugPrint('Could not remember Meditate choices (${error.runtimeType}).');
    });
  }

  Future<void> start() {
    final sound = _state.sound;
    if (sound == null || !_isSetup || isSilencing) {
      return Future<void>.value();
    }
    _sessionId++;
    _historySessionId = newSessionId();
    final command = ++_command;
    _pendingPause = null;
    _needsReload = false;
    _activeElapsed = Duration.zero;
    _streamPosition = Duration.zero;
    _playThroughStart = Duration.zero;
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
    _saveCheckpoint();
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer.periodic(checkpointInterval, (_) => _checkpoint());
    return _ownership.run(
      owner: this,
      deactivate: end,
      action: () async {
        if (!await _requestFocus(entry, command)) return;
        // A previous session may have ended faded out.
        try {
          await _player.setVolume(1);
        } catch (error) {
          // Fails like a play failure: no session without audible sound.
          debugPrint('Meditate volume reset failed (${error.runtimeType}).');
          if (identical(_entry, entry)) {
            _returnToSetup(
              errorMessage: 'Could not play ${sound.displayName}.',
            );
          }
          return;
        }
        if (_disposed ||
            !identical(_entry, entry) ||
            _state.status != MeditationSessionStatus.loading ||
            _command != command) {
          return;
        }
        await _player.play(entry);
      },
      canRun: () => !_disposed && identical(_entry, entry),
    );
  }

  Future<void> pause() {
    if (_state.status == MeditationSessionStatus.completed && isFinishingBell) {
      return _pauseCompletionBell();
    }
    if (_state.status != MeditationSessionStatus.running &&
        _state.status != MeditationSessionStatus.loading) {
      return Future<void>.value();
    }
    ++_command;
    final entry = _entry;
    if (_countingSince != null) _stopCounting();
    _streamWatchdog?.cancel();
    _streamWatchdog = null;
    _setState(_state.copyWith(status: MeditationSessionStatus.paused));
    _saveCheckpoint();
    // Stopping a repeat reload keeps a paused session silent.
    late final Future<void> pending;
    pending =
        (_player.state.status == LocalPlaybackStatus.playing
                ? _player.pause()
                : _player.stop())
            .catchError((Object error) {
              if (identical(_entry, entry) &&
                  identical(_pendingPause, pending)) {
                _interruptPlayback(
                  'Could not pause the sound. Resume to try again.',
                );
              }
            })
            .whenComplete(() {
              if (identical(_pendingPause, pending)) _pendingPause = null;
            });
    _pendingPause = pending;
    return pending;
  }

  Future<void> _pauseCompletionBell() async {
    ++_command;
    _pendingStops++;
    _finishingBell = null;
    notifyListeners();
    try {
      await _bell.stop();
    } catch (_) {
      _stopFailed = true;
      _setState(
        _state.copyWith(
          errorMessage: 'Could not silence the bell. Try End again.',
        ),
      );
    } finally {
      _pendingStops--;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> resume() async {
    final entry = _entry;
    if (entry == null ||
        _state.status != MeditationSessionStatus.paused ||
        isSilencing) {
      return;
    }
    final command = ++_command;
    final nextStatus = _isStream || _needsReload
        ? MeditationSessionStatus.loading
        : MeditationSessionStatus.running;
    _setState(_state.copyWith(status: nextStatus, clearError: true));
    // Decide how to continue only once the native pause has landed.
    await _pendingPause;
    if (_command != command ||
        _state.status != nextStatus ||
        !identical(_entry, entry)) {
      return;
    }
    if (!await _requestFocus(entry, command)) return;
    if (_isStream) {
      await _player.play(entry, position: _streamPosition);
    } else if (_needsReload) {
      await _player.play(entry, position: _resumePosition);
    } else if (_player.state.status == LocalPlaybackStatus.paused) {
      await _player.resume();
    } else {
      _playThroughStart = _activeElapsed;
      await _player.play(entry);
    }
  }

  Future<bool> _requestFocus(QueueEntry entry, int command) async {
    bool granted;
    try {
      granted = await (_acquireAudioFocus?.call() ?? Future.value(true));
    } catch (_) {
      granted = false;
    }
    if (_disposed || !identical(_entry, entry) || command != _command) {
      return false;
    }
    if (!granted) {
      if (_countingSince != null) _stopCounting();
      _setState(
        _state.copyWith(
          status: MeditationSessionStatus.paused,
          errorMessage: 'Audio is unavailable. Resume to try again.',
        ),
      );
      _saveCheckpoint();
    }
    return granted;
  }

  /// Also silences a ringing bell, so another mode never sounds over it.
  Future<void> end() async {
    if (_isSetup && _entry == null && !isSilencing) return;
    _pendingStops++;
    _returnToSetup();
    try {
      await Future.wait([_player.stop(pauseOnFailure: true), _bell.stop()]);
      _stopFailed = false;
    } catch (_) {
      _stopFailed = true;
      _finishingBell = null;
      _setState(
        _state.copyWith(
          status: MeditationSessionStatus.paused,
          errorMessage: 'Could not silence the sound. Try End again.',
        ),
      );
    } finally {
      _pendingStops--;
      if (!_disposed) notifyListeners();
    }
  }

  void _returnToSetup({String? errorMessage}) {
    _resolve(
      remaining == Duration.zero
          ? SessionOutcome.completed
          : SessionOutcome.endedEarly,
    );
    ++_command;
    _finishingBell = null;
    _streamWatchdog?.cancel();
    _streamWatchdog = null;
    if (_countingSince != null) _stopCounting();
    _activeElapsed = Duration.zero;
    _entry = null;
    _setState(
      _state.copyWith(
        status: MeditationSessionStatus.setup,
        errorMessage: errorMessage,
        clearError: errorMessage == null,
      ),
    );
  }

  void _onPlayerChanged() {
    final status = _state.status;
    if (_isStream &&
        status == MeditationSessionStatus.paused &&
        _player.state.status == LocalPlaybackStatus.error) {
      _interruptPlayback(_player.state.errorMessage);
      return;
    }
    if (status != MeditationSessionStatus.loading &&
        status != MeditationSessionStatus.running) {
      return;
    }
    if (_isStream) {
      _onStreamChanged();
      return;
    }
    switch (_player.state.status) {
      case LocalPlaybackStatus.playing
          when _countingSince == null && _pendingPause == null:
        _needsReload = false;
        _setState(_state.copyWith(status: MeditationSessionStatus.running));
        _startCounting();
      case LocalPlaybackStatus.completed when _countingSince != null:
        // A sound shorter than the session repeats; the reload is not counted.
        _stopCounting();
        if (_activeElapsed - _playThroughStart < minimumPlayThrough) {
          _returnToSetup(
            errorMessage:
                '${_state.sound!.displayName} is too short to repeat.',
          );
          return;
        }
        _playThroughStart = _activeElapsed;
        unawaited(_player.play(_entry!));
      case LocalPlaybackStatus.error when _needsReload:
        // Restored progress stays paused for a later Resume or End.
        _interruptPlayback(_player.state.errorMessage);
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
    // Volume follows remaining active time, so a paused fade resumes in place.
    final untilFade = remaining - fadeDuration;
    _fade = Timer(untilFade > Duration.zero ? untilFade : Duration.zero, () {
      _applyFade();
      _fade = Timer.periodic(_fadeStep, (_) => _applyFade());
    });
  }

  void _applyFade() {
    final level = remaining.inMicroseconds / fadeDuration.inMicroseconds;
    // A missed step is only less smooth: the deadline still stops the sound.
    unawaited(
      _player.setVolume(level.clamp(0.0, 1.0)).catchError((Object error) {
        debugPrint('Meditate fade step failed (${error.runtimeType}).');
      }),
    );
  }

  void _stopCounting() {
    _deadline?.cancel();
    _refresh?.cancel();
    _fade?.cancel();
    _activeElapsed = _state.duration - remaining;
    _countingSince = null;
  }

  void _checkDeadline() {
    if (remaining > Duration.zero) return;
    _stopCounting();
    _streamWatchdog?.cancel();
    final entry = _entry;
    _resolve(SessionOutcome.completed);
    _pendingStops++;
    if (_state.isBellEnabled) _finishingBell = entry;
    _setState(_state.copyWith(status: MeditationSessionStatus.completed));
    if (entry != null && identical(_entry, entry)) {
      unawaited(_stopThenRingBell(entry));
    } else {
      // A completion listener can End synchronously and own the native stop.
      _pendingStops--;
      if (!_disposed) notifyListeners();
    }
  }

  /// Records the session once and drops its recovery checkpoint.
  void _resolve(SessionOutcome outcome) {
    final id = _historySessionId;
    if (id == null) return;
    _historySessionId = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _clearCheckpoint();
    final actual = _state.duration - remaining;
    unawaited(
      _history
          ?.record(
            _state.duration,
            id: id,
            actualDuration: actual,
            mode: SessionMode.meditate,
            outcome: outcome,
          )
          .catchError((Object error) {
            debugPrint(
              'Could not save meditation history (${error.runtimeType}).',
            );
          }),
    );
  }

  Future<void> _stopThenRingBell(QueueEntry entry) async {
    try {
      await _player.stop(pauseOnFailure: true);
      _stopFailed = false;
    } catch (_) {
      _stopFailed = true;
      _finishingBell = null;
      _setState(
        _state.copyWith(
          status: MeditationSessionStatus.paused,
          errorMessage: 'Could not silence the sound. Try End again.',
        ),
      );
      return;
    } finally {
      _pendingStops--;
      if (!_disposed) notifyListeners();
    }
    if (!_state.isBellEnabled) return;
    bool isCurrent() =>
        !_disposed &&
        identical(_entry, entry) &&
        identical(_finishingBell, entry);

    final bell = this.bell;
    try {
      await _bell.ring(bell, canRun: isCurrent);
      if (isCurrent()) await _bell.playbackFinished;
    } catch (_) {
      // Only the bell failed: the session stays complete and its sound off.
      if (isCurrent()) {
        _setState(
          _state.copyWith(errorMessage: 'Could not play ${bell.displayName}.'),
        );
      }
    } finally {
      if (identical(_finishingBell, entry)) {
        _finishingBell = null;
        if (!_disposed) notifyListeners();
      }
    }
  }

  void _setState(MeditationSessionState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _checkpointTimer?.cancel();
    _streamWatchdog?.cancel();
    _deadline?.cancel();
    _refresh?.cancel();
    _fade?.cancel();
    _player.removeListener(_onPlayerChanged);
    unawaited(
      _bell.dispose().catchError((Object error) {
        debugPrint('Meditate bell disposal failed (${error.runtimeType}).');
      }),
    );
    _ownership.forget(this);
    super.dispose();
  }
}
