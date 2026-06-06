import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../shared/presentation/gradient_background.dart';
import '../../cloud/pcloud/application/pcloud_auth_controller.dart';
import '../../cloud/pcloud/domain/pcloud_config.dart';
import '../../cloud/pcloud/presentation/pcloud_login_dialog.dart';
import '../../library/application/local_wav_picker_service.dart'
    show FilePickerLocalAudioPicker, LocalAudioFilePicker;
import '../application/app_settings_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    AppSettingsController? settingsController,
    PCloudAuthController? pcloudAuthController,
    LocalAudioFilePicker? picker,
  }) : _settingsController = settingsController,
       _pcloudAuthController = pcloudAuthController,
       _picker = picker;

  final AppSettingsController? _settingsController;
  final PCloudAuthController? _pcloudAuthController;
  final LocalAudioFilePicker? _picker;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppSettingsController _settings;
  late final PCloudAuthController _pcloudAuth;
  late final LocalAudioFilePicker _picker;
  bool _dependenciesResolved = false;
  bool _isPicking = false;
  bool _isConnecting = false;
  String? _message;
  String? _pcloudMessage;

  @override
  void initState() {
    super.initState();
    _picker = widget._picker ?? FilePickerLocalAudioPicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesResolved) return;
    _dependenciesResolved = true;
    final needsScope =
        widget._settingsController == null ||
        widget._pcloudAuthController == null;
    final scope = needsScope ? AppScope.of(context) : null;
    _settings = widget._settingsController ?? scope!.appSettingsController;
    _pcloudAuth = widget._pcloudAuthController ?? scope!.pcloudAuthController;
  }

  Future<void> _connectPCloud() async {
    final request = await showPCloudLoginDialog(context);
    if (request == null || !mounted) return;
    setState(() {
      _isConnecting = true;
      _pcloudMessage = null;
    });
    try {
      await _pcloudAuth.login(
        email: request.email,
        password: request.password,
        region: request.region,
      );
    } on PCloudException catch (e) {
      if (mounted) setState(() => _pcloudMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _pcloudMessage = 'Could not connect to pCloud.');
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnectPCloud() => _pcloudAuth.disconnect();

  Future<void> _addCustomBell() async {
    setState(() {
      _isPicking = true;
      _message = null;
    });
    try {
      final picked = await _picker.pickAudioFiles();
      if (!mounted) return;
      if (picked.isEmpty) {
        setState(() => _message = 'No audio file was selected.');
        return;
      }
      await _settings.addCustomBell(picked.first);
      if (!mounted) return;
      setState(() => _message = 'Added "${picked.first.displayName}".');
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Could not add the custom bell.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Widget _buildPCloudCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_queue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'pCloud',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (_pcloudAuth.isConnected)
                  const Icon(Icons.check_circle, color: Colors.greenAccent),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _pcloudAuth.isConnected
                  ? 'Connected. Browse your pCloud audio from the Library.'
                  : 'Connect with your pCloud email and password to stream '
                        'audio from your account.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            if (_pcloudMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _pcloudMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: _pcloudAuth.isConnected
                  ? OutlinedButton.icon(
                      onPressed: _disconnectPCloud,
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Disconnect'),
                    )
                  : FilledButton.icon(
                      onPressed: _isConnecting ? null : _connectPCloud,
                      icon: _isConnecting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login, size: 18),
                      label: Text(_isConnecting ? 'Connecting…' : 'Connect'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_settings, _pcloudAuth]),
            builder: (context, _) {
              final customBells = _settings.customBells;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPCloudCard(context),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Bell preferences',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              FilledButton.icon(
                                onPressed: _isPicking ? null : _addCustomBell,
                                icon: _isPicking
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.add, size: 18),
                                label: Text(
                                  _isPicking ? 'Adding…' : 'Add bell',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add your own audio files to use as the timer\'s '
                            'ending bell. Pick the bell itself in Timer Mode.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                          if (_message != null) ...[
                            const SizedBox(height: 8),
                            Text(_message!),
                          ],
                          const SizedBox(height: 8),
                          if (customBells.isEmpty)
                            const Text('No custom bells yet.')
                          else
                            ...customBells.map(
                              (bell) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.notifications_active),
                                title: Text(bell.displayName),
                                trailing: IconButton(
                                  tooltip: 'Remove ${bell.displayName}',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      _settings.removeCustomBell(bell.id),
                                ),
                              ),
                            ),
                        ],
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
}
