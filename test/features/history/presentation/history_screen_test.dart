import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/history/application/history_controller.dart';
import 'package:my_meditation_app/features/history/domain/meditation_session.dart';
import 'package:my_meditation_app/features/history/infrastructure/shared_preferences_session_repository.dart';
import 'package:my_meditation_app/features/history/presentation/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Progress shows measured time and outcome and labels legacy time unknown',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'sessions_v1': jsonEncode([
          {
            'id': 'legacy',
            'completedAt': '2026-06-05T09:00:00',
            'durationSeconds': 600,
          },
        ]),
      });
      final history = HistoryController(
        repository: SharedPreferencesSessionRepository(),
        clock: () => DateTime(2026, 6, 6),
      );
      await history.record(
        const Duration(minutes: 20),
        id: 'new',
        actualDuration: const Duration(seconds: 12),
        outcome: SessionOutcome.endedEarly,
        mode: SessionMode.meditate,
      );
      await tester.pumpWidget(
        MaterialApp(home: HistoryScreen(historyController: history)),
      );
      expect(find.text('12s active'), findsOneWidget);
      expect(find.textContaining('Ended early'), findsOneWidget);
      expect(find.text('10m historical duration'), findsOneWidget);
      expect(find.textContaining('Actual time unknown'), findsOneWidget);
      history.dispose();
    },
  );
}
