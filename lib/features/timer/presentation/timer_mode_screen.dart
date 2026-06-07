import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../shared/domain/audio_source.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../../settings/application/app_settings_controller.dart';
import '../application/timer_controller.dart';
import '../domain/bell_selection.dart';

class TimerModeScreen extends StatefulWidget {
  const TimerModeScreen({super.key, TimerController? controller})
    : _controller = controller;

  final TimerController? _controller;

  @override
  State<TimerModeScreen> createState() => _TimerModeScreenState();
}

class _TimerModeScreenState extends State<TimerModeScreen> {
  late final TimerController _controller;
  AppSettingsController? _appSettings;
  late final bool _ownsController;
  bool _dependenciesResolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesResolved) return;
    _dependenciesResolved = true;
    final injected = widget._controller;
    _ownsController = injected == null;
    if (injected != null) {
      _controller = injected;
    } else {
      final deps = AppScope.of(context);
      _appSettings = deps.appSettingsController;
      _controller = TimerController(
        repository: deps.timerSettingsRepository,
        sourceResolver: deps.playbackSourceResolver,
        history: deps.historyController,
      );
      _controller.load();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  /// Maps the current [BellSelection] to a dropdown key, falling back to the
  /// first enabled built-in bell if the selected bell was removed or disabled.
  String _currentBellKey(
    BellSelection bell,
    List<AudioSource> customBells,
    List<BuiltInBell> enabledBuiltIns,
  ) {
    if (bell.isCustom) {
      final id = bell.source!.id;
      if (customBells.any((b) => b.id == id)) return 'custom:$id';
      return 'builtin:${enabledBuiltIns.first.id}';
    }
    final name = bell.name;
    if (enabledBuiltIns.any((b) => b.id == name)) return 'builtin:$name';
    return 'builtin:${enabledBuiltIns.first.id}';
  }

  BellSelection? _bellFromKey(String key, List<AudioSource> customBells) {
    if (key.startsWith('custom:')) {
      final id = key.substring('custom:'.length);
      for (final bell in customBells) {
        if (bell.id == id) return BellSelection.custom(bell);
      }
      return null;
    }
    return BellSelection.builtIn(key.substring('builtin:'.length));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timer Mode')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_controller, _appSettings]),
            builder: (context, _) {
              final state = _controller.state;
              final customBells = _appSettings?.customBells ?? const [];
              // Without an AppSettings scope (e.g. in tests) every built-in
              // bell is available.
              final enabledBuiltIns =
                  _appSettings?.enabledBuiltInBells ?? builtInBells;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Meditation timer'),
                  const SizedBox(height: 8),
                  const Text(
                    'Set a duration and choose a bell for session end.',
                  ),
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
                            initialValue: _currentBellKey(
                              state.settings.bell,
                              customBells,
                              enabledBuiltIns,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Ending bell',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final bell in enabledBuiltIns)
                                DropdownMenuItem<String>(
                                  value: 'builtin:${bell.id}',
                                  child: Text(bell.label),
                                ),
                              for (final bell in customBells)
                                DropdownMenuItem<String>(
                                  value: 'custom:${bell.id}',
                                  child: Text(bell.displayName),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              final selection = _bellFromKey(
                                value,
                                customBells,
                              );
                              if (selection != null) {
                                _controller.setBell(selection);
                                // Preview the bell so the user hears their
                                // selection immediately.
                                _controller.previewBell(selection);
                              }
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
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
