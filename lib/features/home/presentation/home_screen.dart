import 'package:flutter/material.dart';

import '../../library/presentation/library_screen.dart';
import '../../music_mode/presentation/music_mode_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../timer/presentation/timer_mode_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Meditation')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose how you want to practice today.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          _HomeFeatureCard(
            title: 'Music Mode',
            description:
                'Create and play named playlists of read-only meditation audio.',
            icon: Icons.queue_music,
            onTap: () => _open(context, const MusicModeScreen()),
          ),
          _HomeFeatureCard(
            title: 'Timer Mode',
            description: 'Set a meditation timer and choose an ending bell.',
            icon: Icons.self_improvement,
            onTap: () => _open(context, const TimerModeScreen()),
          ),
          _HomeFeatureCard(
            title: 'Library',
            description: 'Browse local and cloud audio sources.',
            icon: Icons.library_music,
            onTap: () => _open(context, const LibraryScreen()),
          ),
          _HomeFeatureCard(
            title: 'Settings',
            description: 'Manage preferences and cloud source connections.',
            icon: Icons.settings,
            onTap: () => _open(context, const SettingsScreen()),
          ),
          const SizedBox(height: 16),
          Card(
            color: colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Source audio files are treated as read-only. The app stores '
                'playlist metadata separately and never edits your music files.',
                style: TextStyle(color: colorScheme.onSecondaryContainer),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _HomeFeatureCard extends StatelessWidget {
  const _HomeFeatureCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
