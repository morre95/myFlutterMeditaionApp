import '../../../shared/domain/audio_source.dart';
import '../../timer/domain/bell_selection.dart';

/// The durable progress of an unfinished session, restored after termination.
class MeditationCheckpoint {
  const MeditationCheckpoint({
    required this.sessionId,
    required this.sound,
    required this.plannedDuration,
    required this.activeDuration,
    required this.soundPosition,
    required this.bell,
    required this.isBellEnabled,
  });

  factory MeditationCheckpoint.fromJson(Map<String, dynamic> json) {
    return MeditationCheckpoint(
      sessionId: json['sessionId'] as String,
      sound: AudioSource.fromJson(json['sound'] as Map<String, dynamic>),
      plannedDuration: Duration(
        microseconds: json['plannedMicroseconds'] as int,
      ),
      activeDuration: Duration(microseconds: json['activeMicroseconds'] as int),
      soundPosition: Duration(
        microseconds: json['soundPositionMicroseconds'] as int,
      ),
      bell: BellSelection.fromJson(json['bell'] as Map<String, dynamic>),
      isBellEnabled: json['bellEnabled'] as bool,
    );
  }

  /// The history identity the session is recorded under when it resolves.
  final String sessionId;
  final AudioSource sound;
  final Duration plannedDuration;

  /// Active meditation time measured before this checkpoint.
  final Duration activeDuration;

  /// Where the sound continues from on Resume.
  final Duration soundPosition;
  final BellSelection bell;
  final bool isBellEnabled;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'sound': sound.toJson(),
    'plannedMicroseconds': plannedDuration.inMicroseconds,
    'activeMicroseconds': activeDuration.inMicroseconds,
    'soundPositionMicroseconds': soundPosition.inMicroseconds,
    'bell': bell.toJson(),
    'bellEnabled': isBellEnabled,
  };
}
