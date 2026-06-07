/// The activity a session was recorded from.
enum SessionMode { timer, music }

class MeditationSession {
  const MeditationSession({
    required this.id,
    required this.completedAt,
    required this.duration,
    required this.mode,
  });

  factory MeditationSession.fromJson(Map<String, dynamic> json) {
    return MeditationSession(
      id: json['id'] as String,
      completedAt: DateTime.parse(json['completedAt'] as String),
      duration: Duration(seconds: json['durationSeconds'] as int),
      // Sessions persisted before mode tracking default to timer.
      mode: SessionMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => SessionMode.timer,
      ),
    );
  }

  final String id;
  final DateTime completedAt;
  final Duration duration;
  final SessionMode mode;

  Map<String, dynamic> toJson() => {
    'id': id,
    'completedAt': completedAt.toIso8601String(),
    'durationSeconds': duration.inSeconds,
    'mode': mode.name,
  };
}
