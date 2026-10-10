/// The activity a session was recorded from.
enum SessionMode { timer, music, meditate }

enum SessionOutcome { completed, endedEarly }

int _sessionSequence = 0;

/// Created at Start and retained until finalization, independent of track IDs.
String newSessionId() =>
    'session-${DateTime.now().microsecondsSinceEpoch}-${_sessionSequence++}';

class MeditationSession {
  const MeditationSession({
    required this.id,
    required this.completedAt,
    required this.duration,
    required this.mode,
    this.actualDuration,
    this.outcome = SessionOutcome.completed,
    this.plannedDuration,
  });

  factory MeditationSession.fromJson(Map<String, dynamic> json) {
    return MeditationSession(
      id: json['id'] as String,
      completedAt: DateTime.parse(json['completedAt'] as String),
      duration: Duration(seconds: json['durationSeconds'] as int),
      plannedDuration: json.containsKey('plannedMicroseconds')
          ? (json['plannedMicroseconds'] == null
                ? null
                : Duration(microseconds: json['plannedMicroseconds'] as int))
          : Duration(seconds: json['durationSeconds'] as int),
      actualDuration: json['actualMicroseconds'] == null
          ? null
          : Duration(microseconds: json['actualMicroseconds'] as int),
      outcome: json['outcome'] == 'endedEarly'
          ? SessionOutcome.endedEarly
          : SessionOutcome.completed,
      // Sessions persisted before mode tracking default to timer.
      mode: SessionMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => SessionMode.timer,
      ),
    );
  }

  final String id;
  final DateTime completedAt;

  /// Original reported duration, retained for backward compatibility.
  final Duration duration;
  final SessionMode mode;

  /// Requested duration, or known Music metadata; never measured active time.
  final Duration? plannedDuration;
  final Duration? actualDuration;
  final SessionOutcome outcome;

  Map<String, dynamic> toJson() => {
    'id': id,
    'completedAt': completedAt.toIso8601String(),
    'durationSeconds': duration.inSeconds,
    'mode': mode.name,
    'plannedMicroseconds': plannedDuration?.inMicroseconds,
    'actualMicroseconds': actualDuration?.inMicroseconds,
    'outcome': outcome.name,
  };
}
