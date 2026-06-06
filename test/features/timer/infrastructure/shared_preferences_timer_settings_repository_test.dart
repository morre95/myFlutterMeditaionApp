import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/timer/domain/bell_selection.dart';
import 'package:my_meditation_app/features/timer/domain/timer_settings.dart';
import 'package:my_meditation_app/features/timer/infrastructure/shared_preferences_timer_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns null when nothing is saved', () async {
    final repository = SharedPreferencesTimerSettingsRepository();

    expect(await repository.load(), isNull);
  });

  test('persists and restores duration and bell selection', () async {
    final repository = SharedPreferencesTimerSettingsRepository();
    const settings = TimerSettings(
      duration: Duration(minutes: 25),
      bell: BellSelection.builtIn('bell_3'),
    );

    await repository.save(settings);
    final restored = await repository.load();

    expect(restored, isNotNull);
    expect(restored!.duration, const Duration(minutes: 25));
    expect(restored.bell.name, 'bell_3');
  });
}
