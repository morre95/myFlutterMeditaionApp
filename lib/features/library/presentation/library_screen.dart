import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../shared/domain/audio_source.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../../cloud/pcloud/application/pcloud_auth_controller.dart';
import '../../cloud/pcloud/application/pcloud_download_controller.dart';
import '../../cloud/pcloud/application/pcloud_service.dart';
import '../../cloud/pcloud/presentation/pcloud_login_dialog.dart';
import '../../playlists/application/playlist_controller.dart';
import '../../settings/application/app_settings_controller.dart';
import '../application/local_wav_picker_service.dart';
import '../application/device_sound_catalog.dart';
import '../application/local_audio_library.dart';
import 'device_storage_screen.dart';
import 'pcloud_browser_screen.dart';

/// Imports durable local copies, adds pCloud references to playlists, and
/// downloads pCloud audio for offline playback.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final PlaylistController _playlists;
  late final PCloudAuthController _pcloudAuth;
  late final PCloudService _pcloudService;
  late final PCloudDownloadController _pcloudDownloads;
  late final LocalAudioFilePicker _picker;
  late final DeviceSoundCatalog _deviceSounds;
  late final AppSettingsController _appSettings;
  bool _resolved = false;
  bool _busy = false;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    final scope = AppScope.of(context);
    _playlists = scope.playlistController;
    _picker = scope.localAudioPicker;
    _pcloudAuth = scope.pcloudAuthController;
    _pcloudService = scope.pcloudService;
    _pcloudDownloads = scope.pcloudDownloadController;
    _deviceSounds = scope.deviceSoundCatalog;
    _appSettings = scope.appSettingsController;
  }

  /// Ensures there is a target playlist, prompting to pick or create one.
  Future<String?> _resolveTargetPlaylist() async {
    final playlists = _playlists.playlists;
    if (playlists.isEmpty) {
      final name = await _promptName('Create a playlist');
      if (name == null || name.isEmpty) return null;
      final created = await _playlists.create(name);
      return created.id;
    }
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to playlist'),
        children: [
          for (final p in playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p.id),
              child: Text(p.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('__new__'),
            child: const Text('+ New playlist'),
          ),
        ],
      ),
    ).then((value) async {
      if (value == '__new__') {
        final name = await _promptName('Create a playlist');
        if (name == null || name.isEmpty) return null;
        final created = await _playlists.create(name);
        return created.id;
      }
      return value;
    });
  }

  Future<void> _addFromDevice() async {
    final playlistId = await _resolveTargetPlaylist();
    if (playlistId == null || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final sources = await _picker.pickAudioFiles();
      final added = await _playlists.addTracks(playlistId, sources);
      if (!mounted) return;
      setState(
        () => _message = added.isEmpty
            ? 'No audio files were selected.'
            : 'Added ${added.length} file${added.length == 1 ? '' : 's'}.',
      );
    } on AudioImportFailure catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not add files.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectPCloud() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final error = await connectToPCloud(context, _pcloudAuth);
    if (mounted) {
      setState(() {
        _busy = false;
        _message = error;
      });
    }
  }

  Future<void> _browsePCloud() async {
    final playlistId = await _resolveTargetPlaylist();
    if (playlistId == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PCloudBrowserScreen(
          service: _pcloudService,
          downloads: _pcloudDownloads,
          onAddFile: (AudioSource source) async {
            final added = await _playlists.addTracks(playlistId, [source]);
            return added.isNotEmpty;
          },
        ),
      ),
    );
  }

  Future<String?> _promptName(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _playlists,
              _pcloudAuth,
              _appSettings,
            ]),
            builder: (context, _) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Import audio to a playlist. Originals stay unchanged.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.smartphone),
                      title: const Text('Import audio from phone'),
                      subtitle: const Text(
                        'Save a durable copy of audio from this device.',
                      ),
                      trailing: const Icon(Icons.add),
                      onTap: _busy ? null : _addFromDevice,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPCloudCard(),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.storage),
                      title: const Text('Saved sounds'),
                      subtitle: const Text(
                        'See stored sounds and their sizes, or remove copies.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              DeviceStorageScreen(catalog: _deviceSounds),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPCloudCard() {
    if (_appSettings.isOfflineMode) {
      return const Card(
        child: ListTile(
          enabled: false,
          leading: Icon(Icons.cloud_off),
          title: Text('pCloud'),
          subtitle: Text('Unavailable in Offline mode.'),
        ),
      );
    }
    if (!_pcloudAuth.isConnected) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_queue),
          title: const Text('pCloud'),
          subtitle: const Text('Connect to browse your cloud audio.'),
          trailing: const Icon(Icons.login),
          onTap: _busy ? null : _connectPCloud,
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_done),
        title: const Text('pCloud'),
        subtitle: const Text(
          'Browse, add, or download audio from your account.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : _browsePCloud,
      ),
    );
  }
}
