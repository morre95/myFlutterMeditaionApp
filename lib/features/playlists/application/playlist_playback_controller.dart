import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../history/application/history_controller.dart';
import '../../history/domain/meditation_session.dart';
import '../../player/application/local_audio_playback_controller.dart';
import '../../player/domain/queue_entry.dart';
import '../domain/playlist.dart';

enum PlaylistPlaybackStatus { idle, playing, paused, completed, error }

enum PlaylistRepeatMode { off, repeatPlaylist, repeatOne }

class PlaylistPlaybackState {
  const PlaylistPlaybackState({
    required this.status,
    this.activePlaylist,
    this.currentTrackIndex,
    this.errorMessage,
    this.repeatMode = PlaylistRepeatMode.off,
    this.shuffleEnabled = false,
  });

  const PlaylistPlaybackState.idle()
    : status = PlaylistPlaybackStatus.idle,
      activePlaylist = null,
      currentTrackIndex = null,
      errorMessage = null,
      repeatMode = PlaylistRepeatMode.off,
      shuffleEnabled = false;

  final PlaylistPlaybackStatus status;
  final Playlist? activePlaylist;
  final int? currentTrackIndex;
  final String? errorMessage;
  final PlaylistRepeatMode repeatMode;
  final bool shuffleEnabled;

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
    PlaylistRepeatMode? repeatMode,
    bool? shuffleEnabled,
    bool clearError = false,
  }) {
    return PlaylistPlaybackState(
      status: status ?? this.status,
      activePlaylist: activePlaylist ?? this.activePlaylist,
      currentTrackIndex: currentTrackIndex ?? this.currentTrackIndex,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
    );
  }
}

/// Plays all tracks in a [Playlist] in order, advancing automatically on completion.
class PlaylistPlaybackController extends ChangeNotifier {
  PlaylistPlaybackController({
    required LocalAudioPlaybackController player,
    HistoryController? history,
    Random? random,
  }) : _player = player,
       _history = history,
       _random = random ?? Random() {
    player.addListener(_onPlayerStateChanged);
  }

  final LocalAudioPlaybackController _player;
  final HistoryController? _history;
  final Random _random;

  PlaylistPlaybackState _state = const PlaylistPlaybackState.idle();

  /// Track indices in the order they should play. `null` means natural order.
  List<int>? _shuffledOrder;

  /// When true, playback stops after the current track instead of advancing.
  bool _singleTrackMode = false;

  PlaylistPlaybackState get state => _state;

  LocalAudioPlaybackState get trackState => _player.state;

  Future<void> playPlaylist(Playlist playlist, {int startIndex = 0}) async {
    if (playlist.tracks.isEmpty) return;

    await _player.stop();
    _singleTrackMode = false;
    if (_state.shuffleEnabled) {
      _shuffledOrder = _buildShuffledOrder(playlist.tracks.length, startIndex);
    } else {
      _shuffledOrder = null;
    }
    _setState(
      _state.copyWith(
        status: PlaylistPlaybackStatus.playing,
        activePlaylist: playlist,
        currentTrackIndex: startIndex,
        clearError: true,
      ),
    );
    await _playCurrentTrack();
  }

  /// Plays a single track and stops when it finishes (no auto-advance).
  Future<void> playSingleTrack(Playlist playlist, int index) async {
    if (index < 0 || index >= playlist.tracks.length) return;

    await _player.stop();
    _shuffledOrder = null;
    _singleTrackMode = true;
    _setState(
      _state.copyWith(
        status: PlaylistPlaybackStatus.playing,
        activePlaylist: playlist,
        currentTrackIndex: index,
        clearError: true,
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
    await _player.resume();
    _setState(_state.copyWith(status: PlaylistPlaybackStatus.playing));
  }

  Future<void> stop() async {
    await _player.stop();
    final repeat = _state.repeatMode;
    final shuffle = _state.shuffleEnabled;
    _shuffledOrder = null;
    _singleTrackMode = false;
    _setState(
      PlaylistPlaybackState(
        status: PlaylistPlaybackStatus.idle,
        repeatMode: repeat,
        shuffleEnabled: shuffle,
      ),
    );
  }

  Future<void> skipToTrack(int index) async {
    final playlist = _state.activePlaylist;
    if (playlist == null) return;
    if (index < 0 || index >= playlist.tracks.length) return;

    await _player.stop();
    _singleTrackMode = false;
    _setState(
      _state.copyWith(
        status: PlaylistPlaybackStatus.playing,
        currentTrackIndex: index,
        clearError: true,
      ),
    );
    await _playCurrentTrack();
  }

  Future<void> next() async {
    final nextIndex = _nextIndex(
      wrap: _state.repeatMode != PlaylistRepeatMode.off,
    );
    if (nextIndex == null) return;
    await skipToTrack(nextIndex);
  }

  Future<void> previous() async {
    final playlist = _state.activePlaylist;
    if (playlist == null) return;

    final position = _player.state.position;
    if (position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }

    final prevIndex = _previousIndex(
      wrap: _state.repeatMode != PlaylistRepeatMode.off,
    );
    if (prevIndex == null) {
      await _player.seek(Duration.zero);
      return;
    }
    await skipToTrack(prevIndex);
  }

  void setPlaylistRepeatMode(PlaylistRepeatMode mode) {
    if (_state.repeatMode == mode) return;
    _setState(_state.copyWith(repeatMode: mode));
  }

  void cyclePlaylistRepeatMode() {
    final next = switch (_state.repeatMode) {
      PlaylistRepeatMode.off => PlaylistRepeatMode.repeatPlaylist,
      PlaylistRepeatMode.repeatPlaylist => PlaylistRepeatMode.repeatOne,
      PlaylistRepeatMode.repeatOne => PlaylistRepeatMode.off,
    };
    setPlaylistRepeatMode(next);
  }

  void toggleShuffle() {
    final enabling = !_state.shuffleEnabled;
    final playlist = _state.activePlaylist;
    if (enabling && playlist != null) {
      _shuffledOrder = _buildShuffledOrder(
        playlist.tracks.length,
        _state.currentTrackIndex ?? 0,
      );
    } else {
      _shuffledOrder = null;
    }
    _setState(_state.copyWith(shuffleEnabled: enabling));
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

    // A single-track play stops once the track finishes.
    if (_singleTrackMode) {
      _recordCompletedSession(_state.currentTrack?.source.duration);
      _setState(_state.copyWith(status: PlaylistPlaybackStatus.completed));
      return;
    }

    if (_state.repeatMode == PlaylistRepeatMode.repeatOne) {
      _setState(_state.copyWith(status: PlaylistPlaybackStatus.playing));
      _playCurrentTrack();
      return;
    }

    final nextIndex = _nextIndex(
      wrap: _state.repeatMode == PlaylistRepeatMode.repeatPlaylist,
    );
    if (nextIndex == null) {
      _recordCompletedSession(_playlistDuration(playlist));
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

  int? _nextIndex({required bool wrap}) {
    final playlist = _state.activePlaylist;
    final current = _state.currentTrackIndex;
    if (playlist == null || current == null) return null;
    final total = playlist.tracks.length;
    if (total == 0) return null;

    final order = _shuffledOrder;
    if (order != null) {
      final pos = order.indexOf(current);
      if (pos < 0) return null;
      if (pos + 1 < order.length) return order[pos + 1];
      return wrap ? order.first : null;
    }

    if (current + 1 < total) return current + 1;
    return wrap ? 0 : null;
  }

  int? _previousIndex({required bool wrap}) {
    final playlist = _state.activePlaylist;
    final current = _state.currentTrackIndex;
    if (playlist == null || current == null) return null;
    final total = playlist.tracks.length;
    if (total == 0) return null;

    final order = _shuffledOrder;
    if (order != null) {
      final pos = order.indexOf(current);
      if (pos < 0) return null;
      if (pos - 1 >= 0) return order[pos - 1];
      return wrap ? order.last : null;
    }

    if (current - 1 >= 0) return current - 1;
    return wrap ? total - 1 : null;
  }

  List<int> _buildShuffledOrder(int length, int startIndex) {
    final remaining = [
      for (var i = 0; i < length; i++)
        if (i != startIndex) i,
    ]..shuffle(_random);
    return [startIndex, ...remaining];
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

  /// Logs a completed listening session. Skips sessions of unknown length so
  /// they don't pollute the streak with zero-duration entries.
  void _recordCompletedSession(Duration? duration) {
    if (duration == null || duration <= Duration.zero) return;
    unawaited(_history?.record(duration, mode: SessionMode.music));
  }

  Duration _playlistDuration(Playlist playlist) => playlist.tracks.fold(
    Duration.zero,
    (sum, track) => sum + (track.source.duration ?? Duration.zero),
  );

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
