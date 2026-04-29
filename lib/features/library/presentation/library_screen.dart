import 'package:flutter/material.dart';

import '../../../shared/presentation/gradient_background.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              _SourceCard(
                title: 'Local phone storage',
                description:
                    'Pick .wav files from the device without moving them.',
              ),
              _SourceCard(
                title: 'pCloud',
                description:
                    'Primary cloud source target for future integration.',
              ),
              _SourceCard(
                title: 'Google Drive, OneDrive, Dropbox',
                description:
                    'Future providers using the same source abstraction.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(description),
        leading: const Icon(Icons.folder_open),
      ),
    );
  }
}
