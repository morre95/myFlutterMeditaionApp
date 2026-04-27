import 'package:flutter/material.dart';

class TimerModeScreen extends StatelessWidget {
  const TimerModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timer Mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Meditation timer'),
                  SizedBox(height: 8),
                  Text('Set a duration and choose a bell for session end.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
