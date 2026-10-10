import '../../../shared/domain/audio_source.dart';
import '../../timer/domain/bell_selection.dart';

/// The choices a session starts from, remembered between sessions.
class MeditationSettings {
  const MeditationSettings({
    required this.sound,
    required this.duration,
    required this.bell,
    required this.isBellEnabled,
  });

  /// Null until a sound has been chosen.
  final AudioSource? sound;
  final Duration duration;
  final BellSelection bell;
  final bool isBellEnabled;
}
