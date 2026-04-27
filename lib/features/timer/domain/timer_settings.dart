import 'bell_selection.dart';

class TimerSettings {
  const TimerSettings({required this.duration, required this.bell});

  final Duration duration;
  final BellSelection bell;

  TimerSettings copyWith({Duration? duration, BellSelection? bell}) {
    return TimerSettings(
      duration: duration ?? this.duration,
      bell: bell ?? this.bell,
    );
  }
}
