import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../shared/domain/audio_source.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../../favorites/application/favorites_controller.dart';
import '../../library/application/local_wav_picker_service.dart'
    show FilePickerLocalAudioPicker, LocalAudioFilePicker;
import '../../player/application/local_audio_playback_controller.dart';
import '../../playlists/application/playlist_controller.dart';
import '../../playlists/application/playlist_playback_controller.dart';
import '../../playlists/domain/playlist.dart';
import '../application/audio_duration_probe.dart';
import 'now_playing_screen.dart';
import 'widgets/playback_timeline.dart';

class MusicModeScreen extends StatefulWidget {
  const MusicModeScreen({
    super.key,
    PlaylistController? playlistController,
    LocalAudioFilePicker? picker,
    LocalAudioPlaybackController? playbackController,
    FavoritesController? favoritesController,
    AudioDurationProbe? durationProbe,
  }) : _playlistController = playlistController,
       _picker = picker,
       _playbackController = playbackController,
       _favoritesController = favoritesController,
       _durationProbe = durationProbe;

  final PlaylistController? _playlistController;
  final LocalAudioFilePicker? _picker;
  final LocalAudioPlaybackController? _playbackController;
  final FavoritesController? _favoritesController;
  final AudioDurationProbe? _durationProbe;

  @override
  State<MusicModeScreen> createState() => _MusicModeScreenState();
}

class _MusicModeScreenState extends State<MusicModeScreen> {
  late final PlaylistController _playlistController;
  late final LocalAudioFilePicker _picker;
  late final LocalAudioPlaybackController _playbackController;
  late final PlaylistPlaybackController _playlistPlaybackController;
  FavoritesController? _favorites;
  late final AudioDurationProbe _durationProbe;

  late final bool _ownsPlaybackController;
  bool _dependenciesResolved = false;

  bool _isPicking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _ownsPlaybackController = widget._playbackController == null;
    _picker = widget._picker ?? FilePickerLocalAudioPicker();
    _durationProbe = widget._durationProbe ?? const AudioPlayersDurationProbe();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesResolved) return;
    _dependenciesResolved = true;
    // Resolve shared singletons from AppScope unless overridden (tests inject
    // the core controllers to run without an AppScope ancestor).
    final injectedForTest =
        widget._playlistController != null &&
        widget._playbackController != null;
    final scope = injectedForTest ? null : AppScope.of(context);

    _playlistController =
        widget._playlistController ?? scope!.playlistController;
    _playbackController =
        widget._playbackController ??
        LocalAudioPlaybackController(resolver: scope!.playbackSourceResolver);
    _favorites = widget._favoritesController ?? scope?.favoritesController;
    _playlistPlaybackController = PlaylistPlaybackController(
      player: _playbackController,
    );
  }

  @override
  void dispose() {
    _playlistPlaybackController.dispose();
    if (_ownsPlaybackController) {
      _playbackController.dispose();
    }
    super.dispose();
  }

  Future<void> _createPlaylist() async {
    final name = await _showNameDialog(context, title: 'New playlist');
    if (name == null || name.isEmpty) return;
    await _playlistController.create(name);
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
    final name = await _showNameDialog(
      context,
      title: 'Rename playlist',
      initial: playlist.name,
    );
    if (name == null || name.isEmpty) return;
    await _playlistController.rename(playlist.id, name);
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete playlist'),
        content: Text('Delete "${playlist.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final playbackState = _playlistPlaybackController.state;
    if (playbackState.activePlaylist?.id == playlist.id) {
      await _playlistPlaybackController.stop();
    }
    await _playlistController.delete(playlist.id);
  }

  Future<void> _pickAndAddFiles() async {
    final playlistId = _playlistController.selectedId;
    if (playlistId == null) return;

    setState(() {
      _isPicking = true;
      _message = null;
    });

    try {
      final sources = await _picker.pickAudioFiles();
      if (!mounted) return;

      final withDurations = <AudioSource>[];
      for (final source in sources) {
        final duration = await _durationProbe.durationOf(source);
        withDurations.add(
          duration == null ? source : source.copyWith(duration: duration),
        );
      }
      if (!mounted) return;

      final added = await _playlistController.addTracks(
        playlistId,
        withDurations,
      );
      setState(() {
        _message = added.isEmpty
            ? 'No audio files were selected.'
            : 'Added ${added.length} audio file${added.length == 1 ? '' : 's'} to the playlist.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not select audio files.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _playPlaylist(Playlist playlist) async {
    await _playlistPlaybackController.playPlaylist(playlist);
    if (!mounted) return;
    _openNowPlaying();
  }

  void _openNowPlaying() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NowPlayingScreen(
          playlistPlaybackController: _playlistPlaybackController,
          playbackController: _playbackController,
        ),
      ),
    );
  }

  Future<void> _pause() => _playlistPlaybackController.pause();

  Future<void> _resume() => _playlistPlaybackController.resume();

  Future<void> _stop() => _playlistPlaybackController.stop();

  Future<void> _seek(Duration position) => _playbackController.seek(position);

  /// Plays only the tapped track (no auto-advance to the rest of the playlist).
  Future<void> _playTrack(Playlist playlist, int index) async {
    await _playlistPlaybackController.playSingleTrack(playlist, index);
  }

  Future<void> _removeTrack(Playlist playlist, PlaylistTrack track) async {
    final currentTrack = _playlistPlaybackController.state.currentTrack;
    if (currentTrack?.id == track.id) {
      await _playlistPlaybackController.stop();
    }
    await _playlistController.removeTrack(playlist.id, track.id);
  }

  Future<void> _reorderTrack(
    Playlist playlist,
    int oldIndex,
    int newIndex,
  ) async {
    await _playlistController.reorderTrack(
      playlist.id,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  /// Favorite playlists first, each group keeping its original order.
  List<Playlist> _sortedPlaylists(List<Playlist> playlists) {
    final favorites = _favorites;
    if (favorites == null) return playlists;
    final favored = <Playlist>[];
    final rest = <Playlist>[];
    for (final playlist in playlists) {
      (favorites.isPlaylistFavorite(playlist.id) ? favored : rest).add(
        playlist,
      );
    }
    return [...favored, ...rest];
  }

  static Future<String?> _showNameDialog(
    BuildContext context, {
    required String title,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _NameDialog(title: title, initial: initial),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music Mode')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _playlistController,
              _playbackController,
              _playlistPlaybackController,
              _favorites,
            ]),
            builder: (context, _) {
              if (_playlistController.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final playlists = _sortedPlaylists(_playlistController.playlists);
              final selectedId = _playlistController.selectedId;
              final selected = _playlistController.selectedPlaylist;
              final playbackState = _playlistPlaybackController.state;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _PlaylistListPanel(
                    playlists: playlists,
                    selectedId: selectedId,
                    playbackState: playbackState,
                    favorites: _favorites,
                    onCreate: _createPlaylist,
                    onSelect: _playlistController.select,
                    onPlay: _playPlaylist,
                    onRename: _renamePlaylist,
                    onDelete: _deletePlaylist,
                    onToggleFavorite: _favorites == null
                        ? null
                        : (playlist) => _favorites!.togglePlaylist(playlist.id),
                  ),
                  const SizedBox(height: 12),
                  _PlaybackPanel(
                    state: playbackState,
                    trackState: _playlistPlaybackController.trackState,
                    onPause: playbackState.canPause ? _pause : null,
                    onResume:
                        playbackState.status == PlaylistPlaybackStatus.paused
                        ? _resume
                        : null,
                    onStop: playbackState.canStop ? _stop : null,
                    onSeek: _seek,
                    onOpenNowPlaying: playbackState.activePlaylist != null
                        ? _openNowPlaying
                        : null,
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 12),
                    _TrackListPanel(
                      playlist: selected,
                      playbackState: playbackState,
                      favorites: _favorites,
                      isPicking: _isPicking,
                      message: _message,
                      onPickFiles: _pickAndAddFiles,
                      onPlayTrack: (index) => _playTrack(selected, index),
                      onRemoveTrack: (track) => _removeTrack(selected, track),
                      onReorder: (o, n) => _reorderTrack(selected, o, n),
                      onToggleFavorite: _favorites == null
                          ? null
                          : (track) => _favorites!.toggleTrack(track.id),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const _ReadOnlyNotice(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playlist list panel
// ---------------------------------------------------------------------------

class _PlaylistListPanel extends StatelessWidget {
  const _PlaylistListPanel({
    required this.playlists,
    required this.selectedId,
    required this.playbackState,
    required this.favorites,
    required this.onCreate,
    required this.onSelect,
    required this.onPlay,
    required this.onRename,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  final List<Playlist> playlists;
  final String? selectedId;
  final PlaylistPlaybackState playbackState;
  final FavoritesController? favorites;
  final VoidCallback onCreate;
  final ValueChanged<String> onSelect;
  final ValueChanged<Playlist> onPlay;
  final ValueChanged<Playlist> onRename;
  final ValueChanged<Playlist> onDelete;
  final ValueChanged<Playlist>? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Playlists',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New'),
                ),
              ],
            ),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No playlists yet. Tap New to create one.'),
              )
            else
              ...playlists.map((playlist) {
                final isSelected = playlist.id == selectedId;
                final isPlaying =
                    playbackState.activePlaylist?.id == playlist.id &&
                    playbackState.isPlayingPlaylist;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isPlaying
                        ? Icons.volume_up
                        : isSelected
                        ? Icons.playlist_play
                        : Icons.queue_music,
                  ),
                  title: Text(
                    playlist.name,
                    style: isSelected
                        ? TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                  ),
                  subtitle: Text(
                    '${playlist.tracks.length} track${playlist.tracks.length == 1 ? '' : 's'}',
                  ),
                  onTap: () => onSelect(playlist.id),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      if (onToggleFavorite != null)
                        IconButton(
                          tooltip: 'Favorite ${playlist.name}',
                          onPressed: () => onToggleFavorite!(playlist),
                          icon: Icon(
                            favorites?.isPlaylistFavorite(playlist.id) ?? false
                                ? Icons.star
                                : Icons.star_border,
                            color:
                                (favorites?.isPlaylistFavorite(playlist.id) ??
                                    false)
                                ? Colors.amber
                                : null,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Play ${playlist.name}',
                        onPressed: playlist.tracks.isEmpty
                            ? null
                            : () => onPlay(playlist),
                        icon: const Icon(Icons.play_arrow),
                      ),
                      PopupMenuButton<_PlaylistAction>(
                        onSelected: (action) {
                          switch (action) {
                            case _PlaylistAction.rename:
                              onRename(playlist);
                            case _PlaylistAction.delete:
                              onDelete(playlist);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _PlaylistAction.rename,
                            child: Text('Rename'),
                          ),
                          PopupMenuItem(
                            value: _PlaylistAction.delete,
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

enum _PlaylistAction { rename, delete }

// ---------------------------------------------------------------------------
// Playback panel
// ---------------------------------------------------------------------------

class _PlaybackPanel extends StatelessWidget {
  const _PlaybackPanel({
    required this.state,
    required this.trackState,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSeek,
    required this.onOpenNowPlaying,
  });

  final PlaylistPlaybackState state;
  final LocalAudioPlaybackState trackState;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onOpenNowPlaying;

  @override
  Widget build(BuildContext context) {
    final currentTrack = state.currentTrack;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenNowPlaying,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Playback',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (onOpenNowPlaying != null)
                    const Icon(Icons.open_in_full, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Text(_statusText),
              if (state.activePlaylist != null) ...[
                const SizedBox(height: 4),
                Text('Playlist: ${state.activePlaylist!.name}'),
              ],
              if (currentTrack != null) ...[
                const SizedBox(height: 4),
                Text('Now playing: ${currentTrack.source.displayName}'),
              ],
              const SizedBox(height: 12),
              PlaybackTimeline(state: trackState, onSeek: onSeek),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _statusText {
    return switch (state.status) {
      PlaylistPlaybackStatus.idle => 'Nothing playing.',
      PlaylistPlaybackStatus.playing => 'Playing.',
      PlaylistPlaybackStatus.paused => 'Paused.',
      PlaylistPlaybackStatus.completed => 'Playlist finished.',
      PlaylistPlaybackStatus.error => 'Playback error.',
    };
  }
}

// ---------------------------------------------------------------------------
// Track list panel for selected playlist
// ---------------------------------------------------------------------------

class _TrackListPanel extends StatelessWidget {
  const _TrackListPanel({
    required this.playlist,
    required this.playbackState,
    required this.favorites,
    required this.isPicking,
    required this.message,
    required this.onPickFiles,
    required this.onPlayTrack,
    required this.onRemoveTrack,
    required this.onReorder,
    required this.onToggleFavorite,
  });

  final Playlist playlist;
  final PlaylistPlaybackState playbackState;
  final FavoritesController? favorites;
  final bool isPicking;
  final String? message;
  final VoidCallback onPickFiles;
  final ValueChanged<int> onPlayTrack;
  final ValueChanged<PlaylistTrack> onRemoveTrack;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<PlaylistTrack>? onToggleFavorite;

  static String _trackSubtitle(AudioSource source) {
    final kind = source.kind == AudioSourceKind.pCloud
        ? 'pCloud'
        : 'Local file';
    final duration = source.duration;
    if (duration == null) return kind;
    return '$kind · ${_formatDuration(duration)}';
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final tracks = playlist.tracks;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    playlist.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: isPicking ? null : onPickFiles,
                  icon: isPicking
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.library_music, size: 18),
                  label: Text(isPicking ? 'Selecting…' : 'Add files'),
                ),
              ],
            ),
            if (message != null) ...[const SizedBox(height: 8), Text(message!)],
            const SizedBox(height: 8),
            if (tracks.isEmpty)
              const Text('No tracks yet. Tap Add files to pick audio.')
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tracks.length,
                onReorderItem: onReorder,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final isCurrentTrack =
                      playbackState.currentTrack?.id == track.id;

                  return ListTile(
                    key: ValueKey(track.id),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isCurrentTrack ? Icons.volume_up : Icons.audio_file,
                    ),
                    title: Text(track.source.displayName),
                    subtitle: Text(_trackSubtitle(track.source)),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        if (onToggleFavorite != null)
                          IconButton(
                            tooltip: 'Favorite ${track.source.displayName}',
                            onPressed: () => onToggleFavorite!(track),
                            icon: Icon(
                              favorites?.isTrackFavorite(track.id) ?? false
                                  ? Icons.star
                                  : Icons.star_border,
                              color:
                                  (favorites?.isTrackFavorite(track.id) ??
                                      false)
                                  ? Colors.amber
                                  : null,
                            ),
                          ),
                        IconButton(
                          tooltip: 'Play ${track.source.displayName}',
                          onPressed: () => onPlayTrack(index),
                          icon: const Icon(Icons.play_arrow),
                        ),
                        IconButton(
                          tooltip: 'Remove ${track.source.displayName}',
                          onPressed: () => onRemoveTrack(track),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Name dialog — owns its TextEditingController so it is disposed with the widget
// ---------------------------------------------------------------------------

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial = ''});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Files stay read-only. Playlists store only app metadata and local '
          'file references.',
          style: TextStyle(color: colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
