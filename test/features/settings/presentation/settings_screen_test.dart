import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_auth_controller.dart';
import 'package:my_meditation_app/features/cloud/pcloud/application/pcloud_session_store.dart';
import 'package:my_meditation_app/features/cloud/pcloud/domain/pcloud_config.dart';
import 'package:my_meditation_app/features/library/application/local_wav_picker_service.dart';
import 'package:my_meditation_app/features/settings/application/app_settings_controller.dart';
import 'package:my_meditation_app/features/settings/infrastructure/shared_preferences_app_settings_repository.dart';
import 'package:my_meditation_app/features/settings/presentation/settings_screen.dart';
import 'package:my_meditation_app/features/timer/domain/bell_selection.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  Future<AppSettingsController> pumpSettings(WidgetTester tester) async {
    final settings = AppSettingsController(repository: _FakeAppSettingsRepository());
    final auth = PCloudAuthController(store: _StubSessionStore());

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settingsController: settings,
          pcloudAuthController: auth,
          picker: const _FakeLocalAudioFilePicker([]),
        ),
      ),
    );
    await tester.pump();
    return settings;
  }

  testWidgets('lists preinstalled bells as active toggles', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Preinstalled'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(builtInBells.length));
    for (final bell in builtInBells) {
      expect(find.text(bell.label), findsOneWidget);
    }
  });

  testWidgets('disabling a preinstalled bell marks it disabled', (tester) async {
    final settings = await pumpSettings(tester);

    // Toggle the first built-in bell off.
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(settings.isBuiltInBellEnabled(builtInBells.first.id), isFalse);
    expect(find.textContaining('Re-enable it any time.'), findsOneWidget);
  });

  testWidgets('blocks disabling the last active preinstalled bell', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);

    // Disable every bell except the last one.
    for (final bell in builtInBells.take(builtInBells.length - 1)) {
      await settings.disableBuiltInBell(bell.id);
    }
    await tester.pumpAndSettle();

    // The last bell is the only one still enabled — try to turn it off.
    final lastSwitch = find.byType(SwitchListTile).last;
    await tester.ensureVisible(lastSwitch);
    await tester.pumpAndSettle();
    await tester.tap(lastSwitch);
    await tester.pumpAndSettle();

    expect(settings.isBuiltInBellEnabled(builtInBells.last.id), isTrue);
    expect(
      find.text('At least one preinstalled bell must stay active.'),
      findsOneWidget,
    );
  });
}

class _FakeAppSettingsRepository implements AppSettingsRepository {
  List<AudioSource> _bells = [];
  Set<String> _disabledBuiltIns = {};

  @override
  Future<List<AudioSource>> loadCustomBells() async => List.from(_bells);

  @override
  Future<void> saveCustomBells(List<AudioSource> bells) async {
    _bells = List.from(bells);
  }

  @override
  Future<Set<String>> loadDisabledBuiltInBells() async =>
      Set.from(_disabledBuiltIns);

  @override
  Future<void> saveDisabledBuiltInBells(Set<String> bellIds) async {
    _disabledBuiltIns = Set.from(bellIds);
  }
}

class _FakeLocalAudioFilePicker implements LocalAudioFilePicker {
  const _FakeLocalAudioFilePicker(this.sources);

  final List<AudioSource> sources;

  @override
  Future<List<AudioSource>> pickAudioFiles() async => sources;
}

class _StubSessionStore implements PCloudSessionStore {
  PCloudSession? _session;

  @override
  Future<PCloudSession?> read() async => _session;

  @override
  Future<void> write(PCloudSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
