import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/timer/application/timer_controller.dart';
import 'package:my_meditation_app/features/timer/application/wake_lock.dart';
import 'package:my_meditation_app/features/timer/presentation/timer_mode_screen.dart';

void main() {
  Future<TimerController> pumpScreen(WidgetTester tester) async {
    // Inject a controller (no repository) so the screen does not require an
    // AppScope ancestor. A fake wakelock keeps the test off the platform plugin.
    final controller = TimerController(wakeLock: _FakeWakeLock());
    await tester.pumpWidget(
      MaterialApp(home: TimerModeScreen(controller: controller)),
    );
    return controller;
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

  testWidgets('disables reset while running and re-enables when paused', (
    tester,
  ) async {
    final controller = await pumpScreen(tester);
    addTearDown(controller.dispose);

    OutlinedButton resetButton() => tester.widget<OutlinedButton>(
      find.byKey(const Key('timer-reset-button')),
    );

    expect(resetButton().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('timer-start-pause-button')));
    await tester.pump();
    expect(controller.state.isRunning, isTrue);
    expect(resetButton().onPressed, isNull);

    await tester.tap(find.byKey(const Key('timer-start-pause-button')));
    await tester.pump();
    expect(controller.state.isPaused, isTrue);
    expect(resetButton().onPressed, isNotNull);
  });
}

class _FakeWakeLock implements WakeLock {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}
