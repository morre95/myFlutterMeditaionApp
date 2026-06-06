import 'package:flutter/material.dart';

import '../application/pcloud_auth_controller.dart';
import '../domain/pcloud_config.dart';

/// Runs the full connect flow: collect credentials, log in, and — if the
/// account uses 2FA — prompt for the authenticator code and complete login.
///
/// Returns null on success or cancellation, or a user-facing error message.
Future<String?> connectToPCloud(
  BuildContext context,
  PCloudAuthController auth,
) async {
  final request = await showPCloudLoginDialog(context);
  if (request == null) return null;

  try {
    await auth.login(
      email: request.email,
      password: request.password,
      region: request.region,
    );
    return null;
  } on PCloudTfaRequiredException catch (tfa) {
    if (!context.mounted) return null;
    final code = await showPCloudCodeDialog(context);
    if (code == null) return null;
    try {
      await auth.verifyTfaCode(
        email: request.email,
        password: request.password,
        region: request.region,
        code: code,
        token: tfa.token,
      );
      return null;
    } on PCloudException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not verify the code.';
    }
  } on PCloudException catch (e) {
    return e.message;
  } catch (_) {
    return 'Could not connect to pCloud.';
  }
}

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

/// Prompts for the pCloud two-factor authentication code. Returns null if
/// cancelled.
Future<String?> showPCloudCodeDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _PCloudCodeDialog(),
  );
}

class _PCloudCodeDialog extends StatefulWidget {
  const _PCloudCodeDialog();

  @override
  State<_PCloudCodeDialog> createState() => _PCloudCodeDialogState();
}

class _PCloudCodeDialogState extends State<_PCloudCodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Two-factor authentication'),
      content: TextField(
        controller: _code,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Authenticator code',
          hintText: '6-digit code',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Verify')),
      ],
    );
  }
}
