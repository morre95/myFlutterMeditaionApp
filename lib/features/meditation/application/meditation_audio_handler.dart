import 'package:audio_service/audio_service.dart';

import 'meditation_session_controller.dart';

/// Android's media session is an adapter over the app-owned meditation session.
/// It never creates a player or starts a new session from a background control.
class MeditationAudioHandler extends BaseAudioHandler {
  MeditationAudioHandler({required MeditationSessionController session})
    : _session = session {
    _session.addListener(_publish);
    _publish();
  }

  final MeditationSessionController _session;

  void _publish() {
    final state = _session.state;
    final active =
        state.status == MeditationSessionStatus.running ||
        state.status == MeditationSessionStatus.loading;
    final paused = state.status == MeditationSessionStatus.paused;
    final stopping = _session.isSilencing;
    final failedStop = _session.hasSilencingError;
    final ended =
        !stopping &&
        (state.status == MeditationSessionStatus.setup ||
            state.status == MeditationSessionStatus.completed);
    mediaItem.add(
      ended
          ? null
          : MediaItem(
              id: _session.sessionId,
              title: state.sound!.displayName,
              album: 'Meditation',
              duration: state.duration,
            ),
    );
    playbackState.add(
      PlaybackState(
        controls: ended || (stopping && !failedStop)
            ? []
            : [
                if (!failedStop)
                  paused ? MediaControl.play : MediaControl.pause,
                const MediaControl(
                  androidIcon: 'drawable/audio_service_stop',
                  label: 'End',
                  action: MediaAction.stop,
                ),
              ],
        androidCompactActionIndices: ended || (stopping && !failedStop)
            ? []
            : failedStop
            ? [0]
            : [0, 1],
        processingState: ended
            ? AudioProcessingState.idle
            : state.status == MeditationSessionStatus.loading
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        // Loading must start the foreground service before focus/playback.
        playing: active || stopping,
        updatePosition: state.duration - _session.remaining,
        speed: state.status == MeditationSessionStatus.running ? 1 : 0,
      ),
    );
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    final token = _session.sessionId;
    if (extras?['sessionId'] != token || !name.endsWith(':$token')) return;
    switch (name.split(':').first) {
      case 'pause':
        await pause();
      case 'resume':
        await play();
      case 'end':
        await stop();
    }
  }

  /// Calls and duck requests both pause; focus recovery never resumes.
  Future<void> handleInterruption({required bool began}) =>
      began ? pause() : Future<void>.value();

  @override
  Future<void> play() => _session.resume();

  @override
  Future<void> pause() => _session.pause();

  @override
  Future<void> stop() => _session.end();

  void dispose() => _session.removeListener(_publish);
}
