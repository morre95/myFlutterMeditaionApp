import 'package:flutter/material.dart';

class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});

  static const List<Color> _colors = [
    Color(0xFF1A1F4A),
    Color(0xFF2A3470),
    Color(0xFF0B0E26),
  ];

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _colors,
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}
