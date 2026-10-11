import 'dart:io';

import 'package:flutter/material.dart';

import '../../../shared/domain/audio_source.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../application/device_sound_catalog.dart';

/// Lists the sounds stored on this device with their sizes and removes device
/// copies on request. Nothing is evicted automatically, and originals and
/// cloud files are never touched.
class DeviceStorageScreen extends StatefulWidget {
  const DeviceStorageScreen({super.key, required this.catalog});

  final DeviceSoundCatalog catalog;

  @override
  State<DeviceStorageScreen> createState() => _DeviceStorageScreenState();
}

class _DeviceStorageScreenState extends State<DeviceStorageScreen> {
  late Future<List<AudioSource>> _sounds = widget.catalog.load();
  String? _message;
  bool _isError = false;

  Future<void> _remove(AudioSource sound) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${sound.displayName}?'),
        content: Text(
          sound.kind == AudioSourceKind.pCloud
              ? 'The copy on this device is deleted. The file stays in '
                    'pCloud and can be downloaded again.'
              : 'The imported copy on this device is deleted. The original '
                    'file is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.catalog.remove(sound);
      _show('Removed ${sound.displayName} from this device.');
    } on SoundInUseException catch (error) {
      _show(error.message, isError: true);
    } on FileSystemException catch (error) {
      debugPrint('Could not remove ${sound.id}: $error');
      _show('Could not remove ${sound.displayName}.', isError: true);
    }
    if (!mounted) return;
    setState(() {
      _sounds = widget.catalog.load();
    });
  }

  void _show(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _isError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved sounds')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: FutureBuilder<List<AudioSource>>(
            future: _sounds,
            builder: (context, snapshot) {
              final sounds = snapshot.data;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Sounds stored on this device play in Offline mode. '
                    'Removing one frees space; originals and pCloud files '
                    'are kept.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      style: _isError
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )
                          : null,
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (snapshot.hasError)
                    Text(
                      'Could not read device storage.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else if (sounds == null)
                    const Center(child: CircularProgressIndicator())
                  else if (sounds.isEmpty)
                    const Text('No sounds are stored on this device.')
                  else ...[
                    Text(
                      'Total ${formatStorageSize(_totalSize(sounds))}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    for (final sound in sounds)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            sound.kind == AudioSourceKind.pCloud
                                ? Icons.cloud_download
                                : Icons.audio_file,
                          ),
                          title: Text(sound.displayName),
                          subtitle: Text(
                            '${sound.kind == AudioSourceKind.pCloud ? 'pCloud download' : 'Imported'}'
                            ' · ${formatStorageSize(sound.storedSize ?? 0)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove ${sound.displayName}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _remove(sound),
                          ),
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

  static int _totalSize(List<AudioSource> sounds) =>
      sounds.fold(0, (total, sound) => total + (sound.storedSize ?? 0));
}

/// Human-readable size of [bytes], using 1024-byte units.
String formatStorageSize(int bytes) {
  const units = ['KB', 'MB', 'GB'];
  if (bytes < 1024) return '$bytes B';
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(1)} ${units[unit]}';
}
