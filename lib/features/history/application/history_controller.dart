import 'package:flutter/foundation.dart';

import '../domain/meditation_session.dart';
import '../infrastructure/shared_preferences_session_repository.dart';

/// Tracks completed meditation sessions and derives a daily streak.
class HistoryController extends ChangeNotifier {
  HistoryController({
    required SessionRepository repository,
    DateTime Function()? clock,
  }) : _repository = repository,
       _now = clock ?? DateTime.now;

  final SessionRepository _repository;
  final DateTime Function() _now;

  List<MeditationSession> _sessions = [];

  /// Sessions most-recent first.
  List<MeditationSession> get sessions {
    final sorted = List<MeditationSession>.from(_sessions)
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return List<MeditationSession>.unmodifiable(sorted);
  }

  int get totalCount => _sessions.length;

  /// Consecutive calendar days (ending today, or yesterday if today has no
  /// session yet) that contain at least one completed session.
  int get currentStreak {
    if (_sessions.isEmpty) return 0;
    final days = _sessions.map((s) => _dateOnly(s.completedAt)).toSet();
    final today = _dateOnly(_now());

    DateTime anchor;
    if (days.contains(today)) {
      anchor = today;
    } else if (days.contains(_previousDay(today))) {
      anchor = _previousDay(today);
    } else {
      return 0;
    }

    var streak = 0;
    var cursor = anchor;
    while (days.contains(cursor)) {
      streak++;
      cursor = _previousDay(cursor);
    }
    return streak;
  }

  Future<void> load() async {
    _sessions = await _repository.loadAll();
    notifyListeners();
  }

  Future<void> record(Duration duration, {required SessionMode mode}) async {
    final completedAt = _now();
    final session = MeditationSession(
      id: 'session-${completedAt.microsecondsSinceEpoch}',
      completedAt: completedAt,
      duration: duration,
      mode: mode,
    );
    _sessions = [..._sessions, session];
    await _repository.saveAll(_sessions);
    notifyListeners();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _previousDay(DateTime d) => DateTime(d.year, d.month, d.day - 1);
}
