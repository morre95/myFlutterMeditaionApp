import 'package:flutter/material.dart';

import '../../../../shared/domain/audio_source.dart';
import '../../../cloud/pcloud/application/pcloud_auth_controller.dart';
import '../../../cloud/pcloud/application/pcloud_service.dart';
import '../../../cloud/pcloud/presentation/pcloud_login_dialog.dart';
import '../../../library/presentation/pcloud_browser_screen.dart';
import '../../../library/application/local_audio_library.dart';
import '../../../settings/application/app_settings_controller.dart';
import '../../../timer/presentation/widgets/bell_dropdown.dart';
import '../../application/meditation_session_controller.dart';

/// Chooses one imported sound, a duration, and the optional ending bell before
/// starting a session.
///
/// The library is read each time setup appears, so it lists current sounds and
/// revalidates the remembered one before Start.
class SessionSetupView extends StatefulWidget {
  const SessionSetupView({
    super.key,
    required this.session,
    required this.library,
    required this.appSettings,
    required this.cloudAuth,
    required this.cloudService,
  });

  final MeditationSessionController session;
  final LocalAudioLibrary library;
  final PCloudAuthController cloudAuth;
  final PCloudService cloudService;

  /// Supplies the enabled built-in bells and custom bells to choose from.
  final AppSettingsController appSettings;

  @override
  State<SessionSetupView> createState() => _SessionSetupViewState();
}

class _SessionSetupViewState extends State<SessionSetupView> {
  late final Future<List<AudioSource>> _sounds = widget.library.loadSounds();

  Future<void> _chooseCloud() async {
    if (!widget.cloudAuth.isConnected) {
      final error = await connectToPCloud(context, widget.cloudAuth);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
      if (!widget.cloudAuth.isConnected) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (browserContext) => PCloudBrowserScreen(
          service: widget.cloudService,
          selectionMode: true,
          onAddFile: (sound) async {
            widget.session.selectSound(sound);
            Navigator.of(browserContext).pop();
            return true;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final state = session.state;
    return FutureBuilder<List<AudioSource>>(
      future: _sounds,
      builder: (context, snapshot) {
        final available = snapshot.data ?? const <AudioSource>[];
        final selected = state.sound?.kind == AudioSourceKind.pCloud
            ? state.sound
            : available
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
                      selected: selected?.kind == AudioSourceKind.localFile
                          ? selected
                          : null,
                      onSelected: session.selectSound,
                    ),
                    TextButton.icon(
                      onPressed: _chooseCloud,
                      icon: const Icon(Icons.cloud_outlined),
                      label: const Text('Choose from pCloud'),
                    ),
                    if (selected?.kind == AudioSourceKind.pCloud)
                      Text(selected!.displayName),
                    if (snapshot.hasData &&
                        state.sound != null &&
                        selected == null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${state.sound!.displayName} is no longer available. '
                        'Choose another sound.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
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
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('meditate-bell-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ring a bell at the end'),
                      value: state.isBellEnabled,
                      onChanged: session.setBellEnabled,
                    ),
                    ListenableBuilder(
                      listenable: widget.appSettings,
                      builder: (context, _) => BellDropdown(
                        selection: state.bell,
                        builtIns: widget.appSettings.enabledBuiltInBells,
                        customBells: widget.appSettings.customBells,
                        onChanged: state.isBellEnabled
                            ? session.selectBell
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: FilledButton(
                onPressed: selected == null
                    ? null
                    : () {
                        // Play the library's current copy, never a
                        // remembered locator that may have moved.
                        session.selectSound(selected);
                        session.start();
                      },
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
