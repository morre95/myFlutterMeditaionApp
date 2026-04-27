import 'package:flutter/material.dart';

import '../../library/application/local_wav_picker_service.dart';
import '../../player/application/local_audio_playback_controller.dart';
import '../../player/application/playback_queue_controller.dart';
import '../../player/domain/queue_entry.dart';

class MusicModeScreen extends StatefulWidget {
  const MusicModeScreen({
    super.key,
    PlaybackQueueController? queueController,
    LocalWavPicker? picker,
    LocalAudioPlaybackController? playbackController,
  }) : _queueController = queueController,
       _picker = picker,
       _playbackController = playbackController;

  final PlaybackQueueController? _queueController;
  final LocalWavPicker? _picker;
  final LocalAudioPlaybackController? _playbackController;

  @override
  State<MusicModeScreen> createState() => _MusicModeScreenState();
}

class _MusicModeScreenState extends State<MusicModeScreen> {
  late final PlaybackQueueController _queueController;
  late final LocalWavPicker _picker;
  late final LocalAudioPlaybackController _playbackController;
  late final bool _ownsQueueController;
  late final bool _ownsPlaybackController;

  bool _isPicking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _ownsQueueController = widget._queueController == null;
    _ownsPlaybackController = widget._playbackController == null;
    _queueController = widget._queueController ?? PlaybackQueueController();
    _picker = widget._picker ?? FilePickerLocalWavPicker();
    _playbackController =
        widget._playbackController ?? LocalAudioPlaybackController();
  }

  @override
  void dispose() {
    if (_ownsQueueController) {
      _queueController.dispose();
    }
    if (_ownsPlaybackController) {
      _playbackController.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFiles() async {
    setState(() {
      _isPicking = true;
      _message = null;
    });

    try {
      final sources = await _picker.pickWavFiles();
      if (!mounted) {
        return;
      }

      final entries = _queueController.addAll(sources);
      setState(() {
        _message = entries.isEmpty
            ? 'No WAV files were selected.'
            : 'Added ${entries.length} WAV file${entries.length == 1 ? '' : 's'} to the queue.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = 'Could not select WAV files.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _play(QueueEntry entry) {
    return _playbackController.play(entry);
  }

  Future<void> _pause() {
    return _playbackController.pause();
  }

  Future<void> _stop() {
    return _playbackController.stop();
  }

  Future<void> _remove(QueueEntry entry) async {
    if (_playbackController.state.currentEntry?.id == entry.id) {
      await _playbackController.stop();
    }
    _queueController.remove(entry.id);
  }

  Future<void> _clearQueue() async {
    await _playbackController.stop();
    _queueController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music Mode')),
      body: AnimatedBuilder(
        animation: Listenable.merge([_queueController, _playbackController]),
        builder: (context, _) {
          final entries = _queueController.entries;
          final playbackState = _playbackController.state;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PickerPanel(
                isPicking: _isPicking,
                message: _message,
                onPickFiles: _pickFiles,
              ),
              const SizedBox(height: 12),
              _PlaybackPanel(
                state: playbackState,
                onPause: playbackState.canPause ? _pause : null,
                onStop: playbackState.canStop ? _stop : null,
              ),
              const SizedBox(height: 12),
              _QueuePanel(
                entries: entries,
                currentEntry: playbackState.currentEntry,
                onPlay: _play,
                onRemove: _remove,
                onClear: entries.isEmpty ? null : _clearQueue,
              ),
              const SizedBox(height: 12),
              const _ReadOnlyNotice(),
            ],
          );
        },
      ),
    );
  }
}

class _PickerPanel extends StatelessWidget {
  const _PickerPanel({
    required this.isPicking,
    required this.message,
    required this.onPickFiles,
  });

  final bool isPicking;
  final String? message;
  final VoidCallback onPickFiles;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Local WAV files',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose one or more local .wav files to add to the queue.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isPicking ? null : onPickFiles,
              icon: isPicking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.library_music),
              label: Text(isPicking ? 'Selecting...' : 'Add .wav files'),
            ),
            if (message != null) ...[const SizedBox(height: 8), Text(message!)],
          ],
        ),
      ),
    );
  }
}

class _PlaybackPanel extends StatelessWidget {
  const _PlaybackPanel({
    required this.state,
    required this.onPause,
    required this.onStop,
  });

  final LocalAudioPlaybackState state;
  final VoidCallback? onPause;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final currentEntry = state.currentEntry;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Playback', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_statusText),
            if (currentEntry != null) ...[
              const SizedBox(height: 4),
              Text('Current: ${currentEntry.source.displayName}'),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 4),
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
                  onPressed: onStop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _statusText {
    return switch (state.status) {
      LocalPlaybackStatus.idle => 'No file is playing.',
      LocalPlaybackStatus.loading => 'Loading audio...',
      LocalPlaybackStatus.playing => 'Playing.',
      LocalPlaybackStatus.paused => 'Paused.',
      LocalPlaybackStatus.completed => 'Playback completed.',
      LocalPlaybackStatus.error => 'Playback failed.',
    };
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.entries,
    required this.currentEntry,
    required this.onPlay,
    required this.onRemove,
    required this.onClear,
  });

  final List<QueueEntry> entries;
  final QueueEntry? currentEntry;
  final ValueChanged<QueueEntry> onPlay;
  final ValueChanged<QueueEntry> onRemove;
  final VoidCallback? onClear;

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
                    'Playback queue',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(onPressed: onClear, child: const Text('Clear')),
              ],
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No WAV files queued yet.'),
              )
            else
              ...entries.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    currentEntry?.id == entry.id
                        ? Icons.volume_up
                        : Icons.audio_file,
                  ),
                  title: Text(entry.source.displayName),
                  subtitle: Text('Local file reference'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Play ${entry.source.displayName}',
                        onPressed: () => onPlay(entry),
                        icon: const Icon(Icons.play_arrow),
                      ),
                      IconButton(
                        tooltip: 'Remove ${entry.source.displayName}',
                        onPressed: () => onRemove(entry),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
          'Files stay read-only. The queue stores only app metadata and local '
          'file references.',
          style: TextStyle(color: colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
