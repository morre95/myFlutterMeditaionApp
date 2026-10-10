import 'package:flutter/material.dart';

/// Remaining session time inside a progress ring.
class CountdownCircle extends StatelessWidget {
  const CountdownCircle({
    super.key,
    required this.progress,
    required this.remaining,
  });

  final double progress;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              key: const Key('countdown-progress-indicator'),
              value: progress,
              strokeWidth: 10,
            ),
            Center(
              child: Text(
                _formatDuration(remaining),
                key: const Key('countdown-remaining-text'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      final hh = hours.toString().padLeft(2, '0');
      return '$hh:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
