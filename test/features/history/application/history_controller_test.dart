import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/history/application/history_controller.dart';
import 'package:my_meditation_app/features/history/domain/meditation_session.dart';
import 'package:my_meditation_app/features/history/infrastructure/shared_preferences_session_repository.dart';

void main() {
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

  @override
  Future<List<MeditationSession>> loadAll() async => List.from(saved);

  @override
  Future<void> saveAll(List<MeditationSession> sessions) async {
    saved = List.from(sessions);
  }
}
