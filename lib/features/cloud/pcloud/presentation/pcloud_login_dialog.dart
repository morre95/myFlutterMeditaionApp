import 'package:flutter/material.dart';

import '../domain/pcloud_config.dart';

class PCloudLoginRequest {
  const PCloudLoginRequest({
    required this.email,
    required this.password,
    required this.region,
  });

  final String email;
  final String password;
  final PCloudRegion region;
}

/// Prompts for pCloud email, password, and data region. Returns null if
/// cancelled.
Future<PCloudLoginRequest?> showPCloudLoginDialog(BuildContext context) {
  return showDialog<PCloudLoginRequest>(
    context: context,
    builder: (_) => const _PCloudLoginDialog(),
  );
}

class _PCloudLoginDialog extends StatefulWidget {
  const _PCloudLoginDialog();

  @override
  State<_PCloudLoginDialog> createState() => _PCloudLoginDialogState();
}

class _PCloudLoginDialogState extends State<_PCloudLoginDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  PCloudRegion _region = PCloudRegion.us;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;
    Navigator.of(context).pop(
      PCloudLoginRequest(email: email, password: password, region: _region),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect to pCloud'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'pCloud email'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _submit(),
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
