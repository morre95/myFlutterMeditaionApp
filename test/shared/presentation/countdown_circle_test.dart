import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/shared/presentation/countdown_circle.dart';

void main() {
  Future<String> shown(WidgetTester tester, Duration remaining) async {
    await tester.pumpWidget(
      MaterialApp(home: CountdownCircle(progress: 0, remaining: remaining)),
    );
    return tester
        .widget<Text>(find.byKey(const Key('countdown-remaining-text')))
        .data!;
  }

  testWidgets('shows whole seconds unchanged', (tester) async {
    expect(await shown(tester, const Duration(minutes: 20)), '20:00');
    expect(
      await shown(tester, const Duration(hours: 1, seconds: 5)),
      '01:00:05',
    );
  });

  testWidgets('rounds partial seconds up like a countdown', (tester) async {
    expect(
      await shown(
        tester,
        const Duration(minutes: 19, seconds: 59, milliseconds: 1),
      ),
      '20:00',
    );
    expect(await shown(tester, const Duration(milliseconds: 400)), '00:01');
    expect(await shown(tester, Duration.zero), '00:00');
  });
}
