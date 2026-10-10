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

  /// Partial seconds round up, so a countdown reaches 00:00 only when done.
  String _formatDuration(Duration duration) {
    final totalSeconds =
        (duration.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
        Duration.microsecondsPerSecond;
    final minutes = (totalSeconds ~/ 60)
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = totalSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = totalSeconds ~/ 3600;
    if (hours > 0) {
      final hh = hours.toString().padLeft(2, '0');
      return '$hh:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
