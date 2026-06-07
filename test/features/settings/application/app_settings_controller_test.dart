import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/settings/application/app_settings_controller.dart';
import 'package:my_meditation_app/features/settings/infrastructure/shared_preferences_app_settings_repository.dart';
import 'package:my_meditation_app/features/timer/domain/bell_selection.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  AudioSource bell(String id) => AudioSource(
    id: id,
    kind: AudioSourceKind.localFile,
    displayName: '$id.mp3',
    reference: '/bells/$id.mp3',
  );

  test('adds, dedupes and removes custom bells', () async {
    final repo = _FakeAppSettingsRepository();
    final controller = AppSettingsController(repository: repo);

    await controller.addCustomBell(bell('gong'));
    await controller.addCustomBell(bell('gong')); // duplicate ignored
    await controller.addCustomBell(bell('chime'));

    expect(controller.customBells.map((b) => b.id), ['gong', 'chime']);

    await controller.removeCustomBell('gong');
    expect(controller.customBells.map((b) => b.id), ['chime']);
  });

  test('load restores persisted custom bells', () async {
    final repo = _FakeAppSettingsRepository();
    await AppSettingsController(repository: repo).addCustomBell(bell('gong'));

    final restored = AppSettingsController(repository: repo);
    await restored.load();

    expect(restored.customBells.map((b) => b.id), ['gong']);
  });

  group('built-in bells', () {
    test('all are enabled by default', () {
      final controller = AppSettingsController(
        repository: _FakeAppSettingsRepository(),
      );

      expect(
        controller.enabledBuiltInBells.map((b) => b.id),
        builtInBells.map((b) => b.id),
      );
    });

    test('disabling hides a bell but keeps it re-enableable', () async {
      final controller = AppSettingsController(
        repository: _FakeAppSettingsRepository(),
      );

      final disabled = await controller.disableBuiltInBell('bell_2');

      expect(disabled, isTrue);
      expect(controller.isBuiltInBellEnabled('bell_2'), isFalse);
      expect(
        controller.enabledBuiltInBells.map((b) => b.id),
        isNot(contains('bell_2')),
      );

      await controller.enableBuiltInBell('bell_2');

      expect(controller.isBuiltInBellEnabled('bell_2'), isTrue);
      expect(
        controller.enabledBuiltInBells.map((b) => b.id),
        contains('bell_2'),
      );
    });

    test('refuses to disable the last enabled bell', () async {
      final controller = AppSettingsController(
        repository: _FakeAppSettingsRepository(),
      );

      // Disable all but the last built-in bell.
      for (final bell in builtInBells.take(builtInBells.length - 1)) {
        expect(await controller.disableBuiltInBell(bell.id), isTrue);
      }

      final last = builtInBells.last;
      final disabledLast = await controller.disableBuiltInBell(last.id);

      expect(disabledLast, isFalse);
      expect(controller.isBuiltInBellEnabled(last.id), isTrue);
      expect(controller.enabledBuiltInBells, [last]);
    });

    test('load restores disabled built-in bells', () async {
      final repo = _FakeAppSettingsRepository();
      await AppSettingsController(
        repository: repo,
      ).disableBuiltInBell('bell_3');

      final restored = AppSettingsController(repository: repo);
      await restored.load();

      expect(restored.isBuiltInBellEnabled('bell_3'), isFalse);
    });
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
