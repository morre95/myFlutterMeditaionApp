import 'package:flutter/material.dart';

import '../../../shared/domain/audio_source.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../../cloud/pcloud/application/pcloud_service.dart';
import '../../cloud/pcloud/domain/pcloud_config.dart';
import '../../cloud/pcloud/domain/pcloud_listing.dart';

/// Browses pCloud folders and lets the user tap audio files to add to a
/// playlist. Returns nothing; additions are reported via [onAddFile].
class PCloudBrowserScreen extends StatefulWidget {
  const PCloudBrowserScreen({
    super.key,
    required this.service,
    required this.onAddFile,
  });

  final PCloudService service;

  /// Called when the user taps an audio file; returns true once it is added.
  final Future<bool> Function(AudioSource source) onAddFile;

  @override
  State<PCloudBrowserScreen> createState() => _PCloudBrowserScreenState();
}

class _PCloudBrowserScreenState extends State<PCloudBrowserScreen> {
  final List<_FolderCrumb> _stack = [
    const _FolderCrumb(id: PCloudService.rootFolderId, name: 'pCloud'),
  ];

  PCloudListing? _listing;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _openFolder(_stack.last);
  }

  Future<void> _openFolder(_FolderCrumb folder) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final listing = await widget.service.listFolder(folder.id);
      if (!mounted) return;
      setState(() => _listing = listing);
    } on PCloudException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this folder.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _enterFolder(PCloudFolder folder) {
    setState(() => _stack.add(_FolderCrumb(id: folder.id, name: folder.name)));
    _openFolder(_stack.last);
  }

  Future<bool> _goBack() async {
    if (_stack.length <= 1) return true;
    setState(() => _stack.removeLast());
    await _openFolder(_stack.last);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_stack.last.name)),
        extendBodyBehindAppBar: true,
        body: GradientBackground(
          child: SafeArea(
            child: Builder(
              builder: (context) {
                if (_isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  );
                }
                if (listing == null) return const SizedBox.shrink();
                if (listing.folders.isEmpty && listing.audioFiles.isEmpty) {
                  return const Center(
                    child: Text('No folders or audio files here.'),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final folder in listing.folders)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.folder),
                          title: Text(folder.name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _enterFolder(folder),
                        ),
                      ),
                    for (final file in listing.audioFiles)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.audio_file),
                          title: Text(file.displayName),
                          trailing: IconButton(
                            tooltip: 'Add to playlist',
                            icon: const Icon(Icons.add),
                            onPressed: () async {
                              final added = await widget.onAddFile(file);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    added
                                        ? 'Added ${file.displayName}.'
                                        : 'Could not add ${file.displayName}.',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderCrumb {
  const _FolderCrumb({required this.id, required this.name});

  final int id;
  final String name;
}
