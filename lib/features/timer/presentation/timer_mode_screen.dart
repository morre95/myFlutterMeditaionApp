import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../shared/presentation/countdown_circle.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../../settings/application/app_settings_controller.dart';
import '../application/timer_controller.dart';
import '../domain/bell_selection.dart';
import 'widgets/bell_dropdown.dart';

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
        ownership: deps.playbackOwnershipController,
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
                  CountdownCircle(
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
                          BellDropdown(
                            key: const Key('timer-bell-dropdown'),
                            selection: state.settings.bell,
                            builtIns: enabledBuiltIns,
                            customBells: customBells,
                            onChanged: (selection) {
                              _controller.setBell(selection);
                              // Preview the bell so the user hears their
                              // selection immediately.
                              _controller.previewBell(selection);
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
          onPressed: state.isRunning ? null : _controller.reset,
          child: const Text('Reset'),
        ),
      ],
    );
  }
}
