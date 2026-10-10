import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/history/application/history_controller.dart';
import 'package:my_meditation_app/features/history/domain/meditation_session.dart';
import 'package:my_meditation_app/features/history/infrastructure/shared_preferences_session_repository.dart';

void main() {
  test(
    'a failed initial load retains the finalized session for a later retry',
    () async {
      final repo = _FakeSessionRepository([])..failNextLoad = true;
      final history = HistoryController(repository: repo);
      await expectLater(
        history.record(
          const Duration(minutes: 1),
          id: 'load-retry',
          actualDuration: const Duration(seconds: 12),
          mode: SessionMode.meditate,
          outcome: SessionOutcome.endedEarly,
        ),
        throwsStateError,
      );
      await history.load();
      await history.record(
        const Duration(minutes: 1),
        id: 'load-retry',
        actualDuration: const Duration(seconds: 99),
        mode: SessionMode.meditate,
      );
      final restored = HistoryController(repository: repo);
      await restored.load();
      expect(
        restored.sessions.single.actualDuration,
        const Duration(seconds: 12),
      );
      expect(restored.sessions.single.outcome, SessionOutcome.endedEarly);
    },
  );

  test(
    'overlapping load and records preserve older data through delayed storage',
    () async {
      final repo =
          _FakeSessionRepository([
              MeditationSession(
                id: 'old',
                completedAt: DateTime(2026),
                duration: const Duration(minutes: 5),
                mode: SessionMode.timer,
              ),
            ])
            ..loadGate = Completer<void>()
            ..saveGate = Completer<void>();
      final history = HistoryController(repository: repo);
      final loading = history.load();
      final first = history.record(
        const Duration(minutes: 1),
        id: 'first',
        mode: SessionMode.timer,
      );
      final second = history.record(
        const Duration(minutes: 2),
        id: 'second',
        mode: SessionMode.music,
      );
      final repeated = history.record(
        const Duration(minutes: 2),
        id: 'second',
        mode: SessionMode.music,
      );
      repo.loadGate!.complete();
      await loading;
      repo.saveGate!.complete();
      await Future.wait([first, second, repeated]);
      final restored = HistoryController(repository: repo);
      await restored.load();
      expect(restored.sessions.map((s) => s.id).toSet(), {
        'old',
        'first',
        'second',
      });
    },
  );

  test(
    'failed persistence is retried on load without losing or duplicating the session',
    () async {
      final repo = _FakeSessionRepository([])..failNextSave = true;
      final history = HistoryController(repository: repo);
      await expectLater(
        history.record(
          const Duration(minutes: 1),
          id: 'retry',
          actualDuration: const Duration(seconds: 15),
          mode: SessionMode.timer,
        ),
        throwsStateError,
      );
      await history.load();
      await history.record(
        const Duration(minutes: 1),
        id: 'retry',
        mode: SessionMode.timer,
      );
      expect(history.sessions.single.id, 'retry');
      expect(
        history.sessions.single.actualDuration,
        const Duration(seconds: 15),
      );
      expect(repo.saved.length, 1);
    },
  );

  test(
    'legacy records survive reload and new writes without invented elapsed time',
    () async {
      SharedPreferences.setMockInitialValues({
        'sessions_v1': jsonEncode([
          {
            'id': 'legacy',
            'completedAt': '2026-03-28T23:59:00',
            'durationSeconds': 600,
          },
        ]),
      });
      var day = DateTime(2026, 3, 29, 0, 1);
      final history = HistoryController(
        repository: SharedPreferencesSessionRepository(),
        clock: () => day,
      );
      await history.load();
      expect(history.sessions.single.actualDuration, isNull);
      expect(history.currentStreak, 1);
      await history.record(
        const Duration(minutes: 1),
        id: 'early',
        actualDuration: const Duration(seconds: 7),
        outcome: SessionOutcome.endedEarly,
        mode: SessionMode.meditate,
      );
      expect(history.currentStreak, 1);
      await history.record(
        const Duration(minutes: 1),
        id: 'done',
        actualDuration: const Duration(minutes: 1),
        mode: SessionMode.meditate,
      );
      final restored = HistoryController(
        repository: SharedPreferencesSessionRepository(),
        clock: () => day,
      );
      await restored.load();
      expect(
        restored.sessions.firstWhere((s) => s.id == 'legacy').actualDuration,
        isNull,
      );
      expect(restored.currentStreak, 2);
      day = DateTime(2026, 3, 31);
      expect(restored.currentStreak, 0);
    },
  );

  test(
    'early-ended sessions persist actual time once and do not earn a streak',
    () async {
      final repo = _FakeSessionRepository([]);
      final history = HistoryController(
        repository: repo,
        clock: () => DateTime(2026, 6, 6),
      );
      await Future.wait([
        history.record(
          const Duration(minutes: 20),
          id: 'same-session',
          actualDuration: const Duration(seconds: 12),
          outcome: SessionOutcome.endedEarly,
          mode: SessionMode.timer,
        ),
        history.record(
          const Duration(minutes: 20),
          id: 'same-session',
          actualDuration: const Duration(seconds: 12),
          outcome: SessionOutcome.endedEarly,
          mode: SessionMode.timer,
        ),
      ]);
      await history.load();
      expect(
        history.sessions.single.actualDuration,
        const Duration(seconds: 12),
      );
      expect(
        history.sessions.single.plannedDuration,
        const Duration(minutes: 20),
      );
      expect(history.sessions.single.outcome, SessionOutcome.endedEarly);
      expect(history.currentStreak, 0);
    },
  );

  MeditationSession sessionOn(DateTime day) => MeditationSession(
    id: 'id-${day.toIso8601String()}',
    completedAt: day,
    duration: const Duration(minutes: 10),
    mode: SessionMode.timer,
  );

  group('currentStreak', () {
    test('is zero with no sessions', () {
      final controller = HistoryController(
        repository: _FakeSessionRepository([]),
        clock: () => DateTime(2026, 6, 6, 9),
      );
      expect(controller.currentStreak, 0);
    });

    test('counts consecutive days ending today', () async {
      final repo = _FakeSessionRepository([
        sessionOn(DateTime(2026, 6, 6, 7)),
        sessionOn(DateTime(2026, 6, 5, 8)),
        sessionOn(DateTime(2026, 6, 4, 20)),
      ]);
      final controller = HistoryController(
        repository: repo,
        clock: () => DateTime(2026, 6, 6, 9),
      );
      await controller.load();

      expect(controller.currentStreak, 3);
    });

    test('stays alive when today has no session but yesterday does', () async {
      final repo = _FakeSessionRepository([
        sessionOn(DateTime(2026, 6, 5, 8)),
        sessionOn(DateTime(2026, 6, 4, 8)),
      ]);
      final controller = HistoryController(
        repository: repo,
        clock: () => DateTime(2026, 6, 6, 9),
      );
      await controller.load();

      expect(controller.currentStreak, 2);
    });

    test(
      'resets when the most recent session is older than yesterday',
      () async {
        final repo = _FakeSessionRepository([
          sessionOn(DateTime(2026, 6, 3, 8)),
        ]);
        final controller = HistoryController(
          repository: repo,
          clock: () => DateTime(2026, 6, 6, 9),
        );
        await controller.load();

        expect(controller.currentStreak, 0);
      },
    );

    test('multiple sessions on the same day count once', () async {
      final repo = _FakeSessionRepository([
        sessionOn(DateTime(2026, 6, 6, 7)),
        sessionOn(DateTime(2026, 6, 6, 21)),
      ]);
      final controller = HistoryController(
        repository: repo,
        clock: () => DateTime(2026, 6, 6, 22),
      );
      await controller.load();

      expect(controller.currentStreak, 1);
      expect(controller.totalCount, 2);
    });
  });

  test('record persists a new session and updates the streak', () async {
    final repo = _FakeSessionRepository([]);
    final controller = HistoryController(
      repository: repo,
      clock: () => DateTime(2026, 6, 6, 9),
    );

    await controller.record(
      const Duration(minutes: 15),
      mode: SessionMode.timer,
    );

    expect(controller.totalCount, 1);
    expect(controller.currentStreak, 1);
    expect(repo.saved.single.duration, const Duration(minutes: 15));
    expect(repo.saved.single.mode, SessionMode.timer);
  });

  test('record tags the session with the given mode', () async {
    final repo = _FakeSessionRepository([]);
    final controller = HistoryController(
      repository: repo,
      clock: () => DateTime(2026, 6, 6, 9),
    );

    await controller.record(
      const Duration(minutes: 20),
      mode: SessionMode.music,
    );

    expect(repo.saved.single.mode, SessionMode.music);
  });
}

class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository(this.saved);

  List<MeditationSession> saved;
  bool failNextSave = false;
  bool failNextLoad = false;
  Completer<void>? loadGate;
  Completer<void>? saveGate;

  @override
  Future<List<MeditationSession>> loadAll() async {
    await loadGate?.future;
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('storage unavailable');
    }
    return List.from(saved);
  }

  @override
  Future<void> saveAll(List<MeditationSession> sessions) async {
    await saveGate?.future;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('disk unavailable');
    }
    saved = List.from(sessions);
  }
}
