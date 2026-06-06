import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../shared/domain/audio_source.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../../cloud/pcloud/application/pcloud_auth_controller.dart';
import '../../cloud/pcloud/application/pcloud_service.dart';
import '../../cloud/pcloud/presentation/pcloud_login_dialog.dart';
import '../../playlists/application/playlist_controller.dart';
import '../application/local_wav_picker_service.dart';
import 'pcloud_browser_screen.dart';

/// Adds audio from local storage or pCloud into a chosen playlist. Source files
/// stay read-only; only references are stored.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final PlaylistController _playlists;
  late final PCloudAuthController _pcloudAuth;
  late final PCloudService _pcloudService;
  final LocalAudioFilePicker _picker = FilePickerLocalAudioPicker();
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
    _pcloudAuth = scope.pcloudAuthController;
    _pcloudService = scope.pcloudService;
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
            animation: Listenable.merge([_playlists, _pcloudAuth]),
            builder: (context, _) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Add audio to a playlist. Your files stay read-only.',
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
                      title: const Text('Local phone storage'),
                      subtitle: const Text(
                        'Pick audio files from this device.',
                      ),
                      trailing: const Icon(Icons.add),
                      onTap: _busy ? null : _addFromDevice,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPCloudCard(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPCloudCard() {
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
        subtitle: const Text('Browse and add audio from your account.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : _browsePCloud,
      ),
    );
  }
}
