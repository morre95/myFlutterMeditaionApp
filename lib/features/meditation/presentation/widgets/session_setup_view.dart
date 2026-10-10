import 'package:flutter/material.dart';

import '../../../../shared/domain/audio_source.dart';
import '../../../library/application/local_audio_library.dart';
import '../../application/meditation_session_controller.dart';

/// Chooses one imported sound and a duration before starting a session.
///
/// The library is read each time setup appears, so it lists current sounds.
class SessionSetupView extends StatefulWidget {
  const SessionSetupView({
    super.key,
    required this.session,
    required this.library,
  });

  final MeditationSessionController session;
  final LocalAudioLibrary library;

  @override
  State<SessionSetupView> createState() => _SessionSetupViewState();
}

class _SessionSetupViewState extends State<SessionSetupView> {
  late final Future<List<AudioSource>> _sounds = widget.library.loadSounds();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final state = session.state;
    return FutureBuilder<List<AudioSource>>(
      future: _sounds,
      builder: (context, snapshot) {
        final available = snapshot.data ?? const <AudioSource>[];
        final selected = available
            .where((sound) => sound.id == state.sound?.id)
            .firstOrNull;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SoundPicker(
                      snapshot: snapshot,
                      selected: selected,
                      onSelected: session.selectSound,
                    ),
                    const SizedBox(height: 16),
                    const Text('Duration (minutes)'),
                    Slider(
                      key: const Key('meditate-duration-slider'),
                      min: MeditationSessionController.minMinutes.toDouble(),
                      max: MeditationSessionController.maxMinutes.toDouble(),
                      divisions:
                          MeditationSessionController.maxMinutes -
                          MeditationSessionController.minMinutes,
                      label: '${state.duration.inMinutes} min',
                      value: state.duration.inMinutes.toDouble(),
                      onChanged: (value) =>
                          session.setDuration(Duration(minutes: value.round())),
                    ),
                    Text('${state.duration.inMinutes} minutes'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: FilledButton(
                onPressed: selected == null ? null : session.start,
                child: const Text('Start'),
              ),
            ),
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
    );
  }
}

class _SoundPicker extends StatelessWidget {
  const _SoundPicker({
    required this.snapshot,
    required this.selected,
    required this.onSelected,
  });

  final AsyncSnapshot<List<AudioSource>> snapshot;
  final AudioSource? selected;
  final ValueChanged<AudioSource> onSelected;

  @override
  Widget build(BuildContext context) {
    if (snapshot.hasError) {
      return Text(
        'Could not load your sounds.',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    final sounds = snapshot.data;
    if (sounds == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('meditate-sounds-loading')),
      );
    }
    if (sounds.isEmpty) {
      return const Text('Import a sound in Library to meditate with it.');
    }
    return DropdownButtonFormField<String>(
      key: const Key('meditate-sound-dropdown'),
      initialValue: selected?.id,
      decoration: const InputDecoration(
        labelText: 'Sound',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final sound in sounds)
          DropdownMenuItem<String>(
            value: sound.id,
            child: Text(sound.displayName),
          ),
      ],
      onChanged: (id) =>
          onSelected(sounds.firstWhere((sound) => sound.id == id)),
    );
  }
}
