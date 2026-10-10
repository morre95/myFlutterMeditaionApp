import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/app/app_dependencies.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_session_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';
import 'package:my_meditation_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders the meditation app foundation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Inject a fake pCloud session store so startup does not touch the real
    // secure-storage plugin (unavailable in the test environment).
    final dependencies = AppDependencies(
      pcloudAuthController: PCloudAuthController(store: _FakeSessionStore()),
    );
    await dependencies.init();

    await tester.pumpWidget(MeditationApp(dependencies: dependencies));
    await tester.pump();

    expect(find.text('My Meditation'), findsOneWidget);
    expect(find.text('Meditate'), findsOneWidget);
    expect(find.text('Music Mode'), findsOneWidget);
    expect(find.text('Timer Mode'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Settings'), 100);
    expect(find.text('Settings'), findsOneWidget);

    expect(
      find.text(
        'Create and play named playlists of read-only meditation audio.',
      ),
      findsOneWidget,
    );

    dependencies.dispose();
  });
}

class _FakeSessionStore implements PCloudSessionStore {
  @override
  Future<PCloudSession?> read() async => null;

  @override
  Future<void> write(PCloudSession session) async {}

  @override
  Future<void> clear() async {}
}
