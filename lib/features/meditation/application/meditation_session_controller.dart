import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/domain/audio_source.dart';
import '../../player/application/local_audio_playback_controller.dart';
import '../../player/application/playback_ownership_controller.dart';
import '../../player/domain/queue_entry.dart';
import '../../settings/application/app_settings_controller.dart';
import '../../timer/application/bell_ringer.dart';
import '../../timer/domain/bell_selection.dart';
import '../domain/meditation_settings.dart';
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
/// Active time is measured with [ElapsedClock] while the sound is audibly
/// playing, so loading gaps and late interface refreshes never change it.
class MeditationSessionController extends ChangeNotifier {
  MeditationSessionController({
    required LocalAudioPlaybackController player,
    required BellRinger bell,
    required MeditationSettingsRepository repository,
    required PlaybackOwnershipController ownership,
    required AppSettingsController appSettings,
    required ElapsedClock clock,
  }) : _player = player,
       _bell = bell,
       _repository = repository,
       _ownership = ownership,
       _appSettings = appSettings,
       _clock = clock {
    _player.addListener(_onPlayerChanged);
  }

  static const int minMinutes = 1;
  static const int maxMinutes = 120;

  /// Shorter play-throughs cannot loop without reloading continuously.
  static const Duration minimumPlayThrough = Duration(seconds: 1);

  /// The sound fades out over this much final active time.
  static const Duration fadeDuration = Duration(seconds: 5);
  static const Duration _fadeStep = Duration(milliseconds: 100);

  final LocalAudioPlaybackController _player;
  final BellRinger _bell;
  final MeditationSettingsRepository _repository;
  final PlaybackOwnershipController _ownership;
  final AppSettingsController _appSettings;
  final ElapsedClock _clock;

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

  /// Restores the last choices. Call once at startup.
  Future<void> load() async {
    final saved = await _repository.load();
    if (saved == null || !_isSetup) return;
    _setState(
      _state.copyWith(
        sound: saved.sound,
        duration: _withinRange(saved.duration),
        bell: saved.bell,
        isBellEnabled: saved.isBellEnabled,
      ),
    );
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
    if (sound == null || !_isSetup) {
      return Future<void>.value();
    }
    _activeElapsed = Duration.zero;
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
    return _ownership.run(
      owner: this,
      deactivate: end,
      action: () async {
        // A previous session may have ended faded out.
        await _player.setVolume(1);
        await _player.play(entry);
      },
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
    late final Future<void> pending;
    pending =
        (_player.state.status == LocalPlaybackStatus.playing
                ? _player.pause()
                : _player.stop())
            .whenComplete(() {
              if (identical(_pendingPause, pending)) _pendingPause = null;
            });
    _pendingPause = pending;
    return pending;
  }

  Future<void> resume() async {
    final entry = _entry;
    if (entry == null || _state.status != MeditationSessionStatus.paused) {
      return;
    }
    _setState(_state.copyWith(status: MeditationSessionStatus.running));
    // Decide how to continue only once the native pause has landed.
    await _pendingPause;
    if (_state.status != MeditationSessionStatus.running ||
        !identical(_entry, entry)) {
      return;
    }
    if (_player.state.status == LocalPlaybackStatus.paused) {
      await _player.resume();
    } else {
      _playThroughStart = _activeElapsed;
      await _player.play(entry);
    }
  }

  /// Also silences a ringing bell, so another mode never sounds over it.
  Future<void> end() async {
    _returnToSetup();
    await Future.wait([_player.stop(), _bell.stop()]);
  }

  void _returnToSetup({String? errorMessage}) {
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
    if (status != MeditationSessionStatus.loading &&
        status != MeditationSessionStatus.running) {
      return;
    }
    switch (_player.state.status) {
      case LocalPlaybackStatus.playing
          when _countingSince == null && _pendingPause == null:
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
    unawaited(_player.setVolume(level.clamp(0.0, 1.0)));
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
    _setState(_state.copyWith(status: MeditationSessionStatus.completed));
    unawaited(_stopThenRingBell(_entry!));
  }

  Future<void> _stopThenRingBell(QueueEntry entry) async {
    await _player.stop();
    if (!_state.isBellEnabled) return;
    bool isCurrent() => !_disposed && identical(_entry, entry);
    final bell = this.bell;
    try {
      await _bell.ring(bell, canRun: isCurrent);
    } catch (_) {
      // Only the bell failed: the session stays complete and its sound off.
      if (isCurrent()) {
        _setState(
          _state.copyWith(errorMessage: 'Could not play ${bell.displayName}.'),
        );
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
