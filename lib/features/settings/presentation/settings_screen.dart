import 'package:flutter/material.dart';

import '../../../shared/presentation/gradient_background.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      extendBodyBehindAppBar: true,
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              Card(
                child: ListTile(
                  leading: Icon(Icons.cloud_queue),
                  title: Text('Cloud sources'),
                  subtitle: Text('Provider connections will be added later.'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: Icon(Icons.notifications_active),
                  title: Text('Bell preferences'),
                  subtitle: Text(
                    'Choose timer bells without changing music files.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
