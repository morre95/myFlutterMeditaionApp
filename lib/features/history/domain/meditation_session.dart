class MeditationSession {
  const MeditationSession({
    required this.id,
    required this.completedAt,
    required this.duration,
  });

  factory MeditationSession.fromJson(Map<String, dynamic> json) {
    return MeditationSession(
      id: json['id'] as String,
      completedAt: DateTime.parse(json['completedAt'] as String),
      duration: Duration(seconds: json['durationSeconds'] as int),
    );
  }

  final String id;
  final DateTime completedAt;
  final Duration duration;

  Map<String, dynamic> toJson() => {
    'id': id,
    'completedAt': completedAt.toIso8601String(),
    'durationSeconds': duration.inSeconds,
  };
}
