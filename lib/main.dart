import 'package:flutter/material.dart';

import 'features/home/presentation/home_screen.dart';

void main() {
  runApp(const MeditationApp());
}

class MeditationApp extends StatelessWidget {
  const MeditationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Meditation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4C6A64)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
