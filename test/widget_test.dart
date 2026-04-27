import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/main.dart';

void main() {
  testWidgets('renders the meditation app foundation', (tester) async {
    await tester.pumpWidget(const MeditationApp());

    expect(find.text('My Meditation'), findsOneWidget);
    expect(find.text('Music Mode'), findsOneWidget);
    expect(find.text('Timer Mode'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.textContaining('Source audio files are treated as read-only'),
      findsOneWidget,
    );
  });
}
