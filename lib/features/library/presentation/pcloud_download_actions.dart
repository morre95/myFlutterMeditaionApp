import 'package:flutter/material.dart';

import '../../../shared/domain/audio_source.dart';
import '../../cloud/pcloud/application/pcloud_download_controller.dart';

/// A pCloud file's offline availability with its Download, Cancel, or Retry
/// action, for use as a list tile subtitle.
class PCloudDownloadActions extends StatelessWidget {
  const PCloudDownloadActions({
    super.key,
    required this.downloads,
    required this.source,
  });

  final PCloudDownloadController downloads;
  final AudioSource source;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final state = downloads.stateOf(source);
        return switch (state.status) {
          PCloudDownloadStatus.notDownloaded => _row(
            const Text('Not downloaded'),
            IconButton(
              tooltip: 'Download ${source.displayName}',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => downloads.download(source),
            ),
          ),
          PCloudDownloadStatus.downloading => _row(
            _progress(state),
            IconButton(
              tooltip: 'Cancel download',
              icon: const Icon(Icons.close),
              onPressed: () => downloads.cancel(source),
            ),
          ),
          PCloudDownloadStatus.available => const Row(
            children: [
              Icon(Icons.offline_pin, size: 16),
              SizedBox(width: 4),
              Text('Available offline'),
            ],
          ),
          PCloudDownloadStatus.failed => _row(
            Text(
              state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            IconButton(
              tooltip: 'Retry download',
              icon: const Icon(Icons.refresh),
              onPressed: () => downloads.download(source),
            ),
          ),
        };
      },
    );
  }

  Widget _row(Widget status, Widget action) {
    return Row(
      children: [
        Expanded(child: status),
        action,
      ],
    );
  }

  Widget _progress(PCloudDownloadState state) {
    final percent = state.progressPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(percent == null ? 'Downloading' : 'Downloading $percent%'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: percent == null ? null : percent / 100),
      ],
    );
  }
}
