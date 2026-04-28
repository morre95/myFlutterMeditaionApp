import 'package:flutter/material.dart';

import '../application/timer_controller.dart';
import '../domain/bell_selection.dart';

class TimerModeScreen extends StatefulWidget {
  const TimerModeScreen({super.key});

  @override
  State<TimerModeScreen> createState() => _TimerModeScreenState();
}

class _TimerModeScreenState extends State<TimerModeScreen> {
  late final TimerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TimerController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timer Mode')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final state = _controller.state;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Meditation timer'),
              const SizedBox(height: 8),
              const Text('Set a duration and choose a bell for session end.'),
              const SizedBox(height: 20),
              _TimerProgressCircle(
                progress: state.progress,
                remaining: state.remaining,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Duration (minutes)'),
                      Slider(
                        key: const Key('timer-duration-slider'),
                        min: 1,
                        max: 120,
                        divisions: 119,
                        label: '${state.settings.duration.inMinutes} min',
                        value: state.settings.duration.inMinutes.toDouble(),
                        onChanged: state.isRunning
                            ? null
                            : (value) {
                                _controller.setDuration(
                                  Duration(minutes: value.round()),
                                );
                              },
                      ),
                      Text('${state.settings.duration.inMinutes} minutes'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const Key('timer-bell-dropdown'),
                        initialValue:
                            state.settings.bell.name ?? builtInBells.first.id,
                        decoration: const InputDecoration(
                          labelText: 'Ending bell',
                          border: OutlineInputBorder(),
                        ),
                        items: builtInBells
                            .map(
                              (bell) => DropdownMenuItem<String>(
                                value: bell.id,
                                child: Text(bell.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          _controller.setBell(BellSelection.builtIn(value));
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildControls(state),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildControls(TimerSessionState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton(
          key: const Key('timer-start-pause-button'),
          onPressed: state.isRunning ? _controller.pause : _controller.start,
          child: Text(state.isRunning ? 'Pause' : 'Start'),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const Key('timer-reset-button'),
          onPressed: _controller.reset,
          child: const Text('Reset'),
        ),
      ],
    );
  }
}

class _TimerProgressCircle extends StatelessWidget {
  const _TimerProgressCircle({required this.progress, required this.remaining});

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
              key: const Key('timer-progress-indicator'),
              value: progress,
              strokeWidth: 10,
            ),
            Center(
              child: Text(
                _formatDuration(remaining),
                key: const Key('timer-remaining-time-text'),
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
