import 'package:flutter/material.dart';

import '../../../shared/presentation/gradient_background.dart';
import '../../history/presentation/history_screen.dart';
import '../../library/presentation/library_screen.dart';
import '../../music_mode/presentation/music_mode_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../timer/presentation/timer_mode_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Meditation')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
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
              const SizedBox(height: 12),
              _HomeFeatureCard(
                title: 'Timer Mode',
                description:
                    'Set a meditation timer and choose an ending bell.',
                icon: Icons.self_improvement,
                onTap: () => _open(context, const TimerModeScreen()),
              ),
              const SizedBox(height: 12),
              _HomeFeatureCard(
                title: 'Library',
                description: 'Browse local and cloud audio sources.',
                icon: Icons.library_music,
                onTap: () => _open(context, const LibraryScreen()),
              ),
              const SizedBox(height: 12),
              _HomeFeatureCard(
                title: 'Progress',
                description: 'See your meditation streak and session history.',
                icon: Icons.insights,
                onTap: () => _open(context, const HistoryScreen()),
              ),
              const SizedBox(height: 12),
              _HomeFeatureCard(
                title: 'Settings',
                description: 'Manage preferences and cloud source connections.',
                icon: Icons.settings,
                onTap: () => _open(context, const SettingsScreen()),
              ),
            ],
          ),
        ),
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
