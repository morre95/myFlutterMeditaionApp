import 'dart:async';

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
  Future<void> _pending = Future<void>.value();
  bool _loaded = false;
  final Map<String, MeditationSession> _unsaved = {};

  Future<void> _savePending() async {
    if (_unsaved.isEmpty) return;
    final next = [..._sessions, ..._unsaved.values];
    await _repository.saveAll(next);
    _sessions = next;
    _unsaved.clear();
  }

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
    final days = _sessions
        .where((s) => s.outcome == SessionOutcome.completed)
        .map((s) => _dateOnly(s.completedAt))
        .toSet();
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

  Future<void> _serialize(Future<void> Function() action) {
    final operation = _pending.then((_) => action());
    // A failed save must not poison later retries.
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _sessions = await _repository.loadAll();
    _loaded = true;
  }

  Future<void> load() => _serialize(() async {
    await _ensureLoaded();
    await _savePending();
    notifyListeners();
  });

  Future<void> record(
    Duration? duration, {
    required SessionMode mode,
    String? id,
    Duration? actualDuration,
    SessionOutcome outcome = SessionOutcome.completed,
  }) {
    final session = MeditationSession(
      id: id ?? newSessionId(),
      completedAt: _now(),
      duration: duration ?? Duration.zero,
      plannedDuration: duration,
      actualDuration: actualDuration ?? duration,
      mode: mode,
      outcome: outcome,
    );
    return _serialize(() async {
      await _ensureLoaded();
      if (_sessions.any((existing) => existing.id == session.id)) return;
      _unsaved.putIfAbsent(session.id, () => session);
      await _savePending();
      notifyListeners();
    });
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _previousDay(DateTime d) => DateTime(d.year, d.month, d.day - 1);
}
