import 'package:flutter/material.dart';

class MusicModeScreen extends StatelessWidget {
  const MusicModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Music Mode')),
      body: const _MusicModeContent(),
    );
  }
}

class _MusicModeContent extends StatelessWidget {
  const _MusicModeContent();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _PlaceholderPanel(
          title: 'Playback queue',
          body:
              'Add read-only .wav files to a queue. Playback support will be '
              'implemented after the core source and queue model is in place.',
        ),
        SizedBox(height: 12),
        _PlaceholderPanel(
          title: 'Audio invariant',
          body:
              'Music files are never edited, renamed, moved, transcoded, or '
              'normalized by the app.',
        ),
      ],
    );
  }
}

class _PlaceholderPanel extends StatelessWidget {
  const _PlaceholderPanel({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}
