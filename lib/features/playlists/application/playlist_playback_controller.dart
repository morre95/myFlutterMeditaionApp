import 'package:flutter/foundation.dart';

import '../../player/application/local_audio_playback_controller.dart';
import '../../player/domain/queue_entry.dart';
import '../domain/playlist.dart';

enum PlaylistPlaybackStatus { idle, playing, paused, completed, error }

class PlaylistPlaybackState {
  const PlaylistPlaybackState({
    required this.status,
    this.activePlaylist,
    this.currentTrackIndex,
    this.errorMessage,
  });

  const PlaylistPlaybackState.idle()
    : status = PlaylistPlaybackStatus.idle,
      activePlaylist = null,
      currentTrackIndex = null,
      errorMessage = null;

  final PlaylistPlaybackStatus status;
  final Playlist? activePlaylist;
  final int? currentTrackIndex;
  final String? errorMessage;

  PlaylistTrack? get currentTrack {
    final p = activePlaylist;
    final i = currentTrackIndex;
    if (p == null || i == null) return null;
    if (i < 0 || i >= p.tracks.length) return null;
    return p.tracks[i];
  }

  bool get isPlayingPlaylist =>
      status == PlaylistPlaybackStatus.playing ||
      status == PlaylistPlaybackStatus.paused;

  bool get canPause => status == PlaylistPlaybackStatus.playing;

  bool get canStop =>
      status == PlaylistPlaybackStatus.playing ||
      status == PlaylistPlaybackStatus.paused ||
      status == PlaylistPlaybackStatus.completed ||
      status == PlaylistPlaybackStatus.error;

  PlaylistPlaybackState copyWith({
    PlaylistPlaybackStatus? status,
    Playlist? activePlaylist,
    int? currentTrackIndex,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlaylistPlaybackState(
      status: status ?? this.status,
      activePlaylist: activePlaylist ?? this.activePlaylist,
      currentTrackIndex: currentTrackIndex ?? this.currentTrackIndex,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Plays all tracks in a [Playlist] in order, advancing automatically on completion.
class PlaylistPlaybackController extends ChangeNotifier {
  PlaylistPlaybackController({required LocalAudioPlaybackController player})
    : _player = player {
    player.addListener(_onPlayerStateChanged);
  }

  final LocalAudioPlaybackController _player;

  PlaylistPlaybackState _state = const PlaylistPlaybackState.idle();

  PlaylistPlaybackState get state => _state;

  LocalAudioPlaybackState get trackState => _player.state;

  Future<void> playPlaylist(Playlist playlist, {int startIndex = 0}) async {
    if (playlist.tracks.isEmpty) return;

    await _player.stop();
    _setState(
      PlaylistPlaybackState(
        status: PlaylistPlaybackStatus.playing,
        activePlaylist: playlist,
        currentTrackIndex: startIndex,
      ),
    );
    await _playCurrentTrack();
  }

  Future<void> pause() async {
    if (_state.status != PlaylistPlaybackStatus.playing) return;
    await _player.pause();
    _setState(_state.copyWith(status: PlaylistPlaybackStatus.paused));
  }

  Future<void> resume() async {
    if (_state.status != PlaylistPlaybackStatus.paused) return;
    final entry = _currentEntry;
    if (entry == null) return;
    await _player.play(entry);
    _setState(_state.copyWith(status: PlaylistPlaybackStatus.playing));
  }

  Future<void> stop() async {
    await _player.stop();
    _setState(const PlaylistPlaybackState.idle());
  }

  Future<void> skipToTrack(int index) async {
    final playlist = _state.activePlaylist;
    if (playlist == null) return;
    if (index < 0 || index >= playlist.tracks.length) return;

    await _player.stop();
    _setState(
      _state.copyWith(
        status: PlaylistPlaybackStatus.playing,
        currentTrackIndex: index,
      ),
    );
    await _playCurrentTrack();
  }

  void _onPlayerStateChanged() {
    final playerState = _player.state;

    if (playerState.status == LocalPlaybackStatus.completed) {
      _advance();
    } else if (playerState.status == LocalPlaybackStatus.error) {
      _setState(
        _state.copyWith(
          status: PlaylistPlaybackStatus.error,
          errorMessage: playerState.errorMessage,
        ),
      );
    }
  }

  void _advance() {
    final playlist = _state.activePlaylist;
    final index = _state.currentTrackIndex;
    if (playlist == null || index == null) return;

    final nextIndex = index + 1;
    if (nextIndex >= playlist.tracks.length) {
      _setState(
        _state.copyWith(
          status: PlaylistPlaybackStatus.completed,
          currentTrackIndex: index,
        ),
      );
      return;
    }

    _setState(
      _state.copyWith(
        status: PlaylistPlaybackStatus.playing,
        currentTrackIndex: nextIndex,
      ),
    );
    _playCurrentTrack();
  }

  Future<void> _playCurrentTrack() async {
    final entry = _currentEntry;
    if (entry == null) return;
    await _player.play(entry);
  }

  QueueEntry? get _currentEntry {
    final track = _state.currentTrack;
    if (track == null) return null;
    return QueueEntry(
      id: track.id,
      source: track.source,
      addedAt: DateTime.now(),
    );
  }

  void _setState(PlaylistPlaybackState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerStateChanged);
    super.dispose();
  }
}
