import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import '../application/meditation_audio_handler.dart';
import '../application/meditation_session_controller.dart';

/// Owns Android's media service and audio focus, not a second audio player.
class MeditationBackgroundAudio {
  MeditationBackgroundAudio._(this._audioSession, this.handler, this._session) {
    _interruptions = _audioSession.interruptionEventStream.listen((event) {
      unawaited(handler.handleInterruption(began: event.begin));
    });
    _noisy = _audioSession.becomingNoisyEventStream.listen((_) {
      unawaited(handler.handleInterruption(began: true));
    });
    _session.addListener(_releaseIfInactive);
  }

  static Future<MeditationBackgroundAudio> init(
    MeditationSessionController session,
  ) async {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
    final handler = await AudioService.init<MeditationAudioHandler>(
      builder: () => MeditationAudioHandler(session: session),
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.example.my_meditation_app.meditation',
        androidNotificationChannelName: 'Meditation',
        androidNotificationIcon: 'drawable/ic_meditation_notification',
        // Release the foreground service and its partial wakelock whenever
        // protected playback ends. stopSelf alone cannot destroy a service
        // still bound to MainActivity. Explicit Resume publishes playing=true
        // before acquiring focus and restarts foreground protection.
        androidStopForegroundOnPause: true,
      ),
    );
    return MeditationBackgroundAudio._(audioSession, handler, session);
  }

  final AudioSession _audioSession;
  final MeditationAudioHandler handler;
  final MeditationSessionController _session;
  late final StreamSubscription<AudioInterruptionEvent> _interruptions;
  late final StreamSubscription<void> _noisy;
  Future<void> _focusCommands = Future<void>.value();
  bool _disposed = false;

  Future<bool> acquireFocus() {
    final result = Completer<bool>();
    _focusCommands = _focusCommands.then((_) async {
      try {
        result.complete(!_disposed && await _audioSession.setActive(true));
      } catch (_) {
        result.complete(false);
      }
    });
    return result.future;
  }

  void _releaseIfInactive() {
    final status = _session.state.status;
    if (_session.isSilencing ||
        _session.isFinishingBell ||
        status == MeditationSessionStatus.loading ||
        status == MeditationSessionStatus.running) {
      return;
    }
    _focusCommands = _focusCommands
        .then((_) async {
          await _audioSession.setActive(false);
        })
        .catchError((Object _) {});
  }

  void dispose() {
    _disposed = true;
    _session.removeListener(_releaseIfInactive);
    _interruptions.cancel();
    _noisy.cancel();
    handler.dispose();
    _focusCommands = _focusCommands
        .then((_) async {
          await _audioSession.setActive(false);
        })
        .catchError((Object _) {});
  }
}
