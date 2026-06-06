import 'package:flutter/material.dart';

import '../application/pcloud_auth_controller.dart';
import '../domain/pcloud_config.dart';

/// Runs the connect flow: collect a pasted access token + region and validate
/// it. Returns null on success or cancellation, or a user-facing error message.
Future<String?> connectToPCloud(
  BuildContext context,
  PCloudAuthController auth,
) async {
  final request = await _showTokenDialog(context);
  if (request == null) return null;
  try {
    await auth.connectWithToken(token: request.token, region: request.region);
    return null;
  } on PCloudException catch (e) {
    return e.message;
  } catch (_) {
    return 'Could not connect to pCloud.';
  }
}

class _TokenRequest {
  const _TokenRequest({required this.token, required this.region});

  final String token;
  final PCloudRegion region;
}

Future<_TokenRequest?> _showTokenDialog(BuildContext context) {
  return showDialog<_TokenRequest>(
    context: context,
    builder: (_) => const _PCloudTokenDialog(),
  );
}

class _PCloudTokenDialog extends StatefulWidget {
  const _PCloudTokenDialog();

  @override
  State<_PCloudTokenDialog> createState() => _PCloudTokenDialogState();
}

class _PCloudTokenDialogState extends State<_PCloudTokenDialog> {
  final _token = TextEditingController();
  PCloudRegion _region = PCloudRegion.us;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    final token = _token.text.trim();
    if (token.isEmpty) return;
    Navigator.of(context).pop(_TokenRequest(token: token, region: _region));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to pCloud'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'pCloud accounts with two-factor authentication must connect with '
            'an access token. Get one by running:\n\n'
            '  rclone authorize "pcloud"\n\n'
            'Sign in (with 2FA) in the browser it opens, then paste the '
            '"access_token" value below.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Access token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PCloudRegion>(
            initialValue: _region,
            decoration: const InputDecoration(labelText: 'Data region'),
            items: [
              for (final region in PCloudRegion.values)
                DropdownMenuItem(value: region, child: Text(region.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _region = value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Connect')),
      ],
    );
  }
}
