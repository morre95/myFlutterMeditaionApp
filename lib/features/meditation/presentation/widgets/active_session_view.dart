import 'package:flutter/material.dart';

import '../../../../shared/presentation/countdown_circle.dart';
import '../../application/meditation_session_controller.dart';

/// Countdown and controls for a session that has started.
class ActiveSessionView extends StatelessWidget {
  const ActiveSessionView({super.key, required this.session});

  final MeditationSessionController session;

  @override
  Widget build(BuildContext context) {
    final state = session.state;
    final remaining = session.remaining;
    final total = state.duration.inMicroseconds;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          state.sound?.displayName ?? '',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        CountdownCircle(
          progress: (total - remaining.inMicroseconds) / total,
          remaining: remaining,
        ),
        const SizedBox(height: 12),
        Text(_statusLabel(state.status), textAlign: TextAlign.center),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            state.errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        _SessionControls(session: session),
      ],
    );
  }

  static String _statusLabel(MeditationSessionStatus status) =>
      switch (status) {
        MeditationSessionStatus.loading => 'Preparing sound…',
        MeditationSessionStatus.paused => 'Paused',
        MeditationSessionStatus.completed => 'Session complete',
        MeditationSessionStatus.setup || MeditationSessionStatus.running => '',
      };
}

class _SessionControls extends StatelessWidget {
  const _SessionControls({required this.session});

  final MeditationSessionController session;

  @override
  Widget build(BuildContext context) {
    final status = session.state.status;
    if (status == MeditationSessionStatus.completed) {
      return Center(
        child: FilledButton(onPressed: session.end, child: const Text('Done')),
      );
    }
    final paused = status == MeditationSessionStatus.paused;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton(
          onPressed: switch (status) {
            MeditationSessionStatus.running => session.pause,
            MeditationSessionStatus.paused => session.resume,
            _ => null,
          },
          child: Text(paused ? 'Resume' : 'Pause'),
        ),
        const SizedBox(width: 12),
        OutlinedButton(onPressed: session.end, child: const Text('End')),
      ],
    );
  }
}
