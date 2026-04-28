import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/timer/presentation/timer_mode_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TimerModeScreen()));
  }

  testWidgets('renders timer controls and progress UI', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Timer Mode'), findsOneWidget);
    expect(find.byKey(const Key('timer-progress-indicator')), findsOneWidget);
    expect(find.byKey(const Key('timer-remaining-time-text')), findsOneWidget);
    expect(find.byKey(const Key('timer-duration-slider')), findsOneWidget);
    expect(find.byKey(const Key('timer-bell-dropdown')), findsOneWidget);
    expect(find.byKey(const Key('timer-start-pause-button')), findsOneWidget);
    expect(find.byKey(const Key('timer-reset-button')), findsOneWidget);
  });

  testWidgets('allows selecting a different built-in bell', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('timer-bell-dropdown')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bell 4').last);
    await tester.pumpAndSettle();

    expect(find.text('Bell 4'), findsOneWidget);
  });
}
