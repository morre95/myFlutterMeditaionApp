import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/app/app_dependencies.dart';
import 'package:my_meditation_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders the meditation app foundation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dependencies = AppDependencies();
    await dependencies.init();

    await tester.pumpWidget(MeditationApp(dependencies: dependencies));
    await tester.pump();

    expect(find.text('My Meditation'), findsOneWidget);
    expect(find.text('Music Mode'), findsOneWidget);
    expect(find.text('Timer Mode'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // The read-only notice sits below the fold; scroll it into view.
    await tester.scrollUntilVisible(
      find.textContaining('Source audio files are treated as read-only'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Source audio files are treated as read-only'),
      findsOneWidget,
    );

    dependencies.dispose();
  });
}
