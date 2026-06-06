import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../application/history_controller.dart';
import '../domain/meditation_session.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, HistoryController? historyController})
    : _historyController = historyController;

  final HistoryController? _historyController;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final HistoryController _history;
  bool _dependenciesResolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesResolved) return;
    _dependenciesResolved = true;
    _history =
        widget._historyController ?? AppScope.of(context).historyController;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _history,
            builder: (context, _) {
              final sessions = _history.sessions;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'Current streak',
                          value: '${_history.currentStreak}',
                          unit: _history.currentStreak == 1 ? 'day' : 'days',
                          icon: Icons.local_fire_department,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: 'Total sessions',
                          value: '${_history.totalCount}',
                          unit: _history.totalCount == 1
                              ? 'session'
                              : 'sessions',
                          icon: Icons.self_improvement,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Recent sessions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (sessions.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No sessions yet. Complete a timer to start your '
                          'streak.',
                        ),
                      ),
                    )
                  else
                    ...sessions.map((s) => _SessionTile(session: s)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(unit),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final MeditationSession session;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.check_circle_outline),
        title: Text('${session.duration.inMinutes} minute session'),
        subtitle: Text(_formatDate(session.completedAt)),
      ),
    );
  }

  String _formatDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
