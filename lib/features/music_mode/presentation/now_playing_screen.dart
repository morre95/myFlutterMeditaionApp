import 'package:flutter/material.dart';

import '../../../shared/presentation/gradient_background.dart';
import '../../player/application/local_audio_playback_controller.dart';
import '../../playlists/application/playlist_playback_controller.dart';
import 'widgets/playback_timeline.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({
    super.key,
    required this.playlistPlaybackController,
    required this.playbackController,
  });

  final PlaylistPlaybackController playlistPlaybackController;
  final LocalAudioPlaybackController playbackController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              playlistPlaybackController,
              playbackController,
            ]),
            builder: (context, _) {
              final state = playlistPlaybackController.state;
              final trackState = playbackController.state;
              return _NowPlayingBody(
                state: state,
                trackState: trackState,
                onShuffleToggle: playlistPlaybackController.toggleShuffle,
                onPrevious: playlistPlaybackController.previous,
                onPlayPause: () {
                  if (state.status == PlaylistPlaybackStatus.playing) {
                    playlistPlaybackController.pause();
                  } else if (state.status == PlaylistPlaybackStatus.paused) {
                    playlistPlaybackController.resume();
                  } else if (state.activePlaylist != null) {
                    playlistPlaybackController.playPlaylist(
                      state.activePlaylist!,
                      startIndex: state.currentTrackIndex ?? 0,
                    );
                  }
                },
                onNext: playlistPlaybackController.next,
                onRepeatCycle:
                    playlistPlaybackController.cyclePlaylistRepeatMode,
                onStop: state.canStop ? playlistPlaybackController.stop : null,
                onSeek: playbackController.seek,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NowPlayingBody extends StatelessWidget {
  const _NowPlayingBody({
    required this.state,
    required this.trackState,
    required this.onShuffleToggle,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onRepeatCycle,
    required this.onStop,
    required this.onSeek,
  });

  final PlaylistPlaybackState state;
  final LocalAudioPlaybackState trackState;
  final VoidCallback onShuffleToggle;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onRepeatCycle;
  final VoidCallback? onStop;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final track = state.currentTrack;
    final isPlaying = state.status == PlaylistPlaybackStatus.playing;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopBar(title: state.activePlaylist?.name ?? 'Now Playing'),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: const _Artwork(),
          ),
          const SizedBox(height: 32),
          Text(
            track?.source.displayName ?? 'No track',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            state.activePlaylist?.name ?? '',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PlaybackTimeline(state: trackState, onSeek: onSeek),
          const SizedBox(height: 16),
          _ControlsRow(
            isPlaying: isPlaying,
            shuffleEnabled: state.shuffleEnabled,
            repeatMode: state.repeatMode,
            onShuffle: onShuffleToggle,
            onPrevious: onPrevious,
            onPlayPause: onPlayPause,
            onNext: onNext,
            onRepeat: onRepeatCycle,
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop, color: Colors.white70),
              label: const Text(
                'Stop',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              state.errorMessage!,
              style: TextStyle(color: colorScheme.error, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          iconSize: 32,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'PLAYING FROM PLAYLIST',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4A6CFF), Color(0xFF8A4FFF), Color(0xFF2A3470)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A6CFF).withValues(alpha: 0.35),
              blurRadius: 60,
              spreadRadius: 4,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.self_improvement, color: Colors.white, size: 96),
        ),
      ),
    );
  }
}

class _ControlsRow extends StatelessWidget {
  const _ControlsRow({
    required this.isPlaying,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.onShuffle,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onRepeat,
  });

  final bool isPlaying;
  final bool shuffleEnabled;
  final PlaylistRepeatMode repeatMode;
  final VoidCallback onShuffle;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final repeatIcon = repeatMode == PlaylistRepeatMode.repeatOne
        ? Icons.repeat_one
        : Icons.repeat;
    final repeatActive = repeatMode != PlaylistRepeatMode.off;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _RoundIconButton(
          icon: Icons.shuffle,
          tooltip: shuffleEnabled ? 'Shuffle on' : 'Shuffle off',
          active: shuffleEnabled,
          onPressed: onShuffle,
        ),
        _RoundIconButton(
          icon: Icons.skip_previous,
          tooltip: 'Previous',
          onPressed: onPrevious,
          size: 36,
        ),
        _PlayPauseButton(isPlaying: isPlaying, onPressed: onPlayPause),
        _RoundIconButton(
          icon: Icons.skip_next,
          tooltip: 'Next',
          onPressed: onNext,
          size: 36,
        ),
        _RoundIconButton(
          icon: repeatIcon,
          tooltip: switch (repeatMode) {
            PlaylistRepeatMode.off => 'Repeat off',
            PlaylistRepeatMode.repeatPlaylist => 'Repeat playlist',
            PlaylistRepeatMode.repeatOne => 'Repeat one',
          },
          active: repeatActive,
          onPressed: onRepeat,
          activeColor: colorScheme.primary,
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 28,
    this.activeColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  final double size;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = active
        ? (activeColor ?? colorScheme.primary)
        : Colors.white.withValues(alpha: 0.85);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: size, color: color),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.isPlaying, required this.onPressed});

  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primary,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: colorScheme.primary.withValues(alpha: 0.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            size: 40,
            color: colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
}
