import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/settings/application/app_settings_controller.dart';
import 'package:my_meditation_app/features/settings/infrastructure/shared_preferences_app_settings_repository.dart';
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
}

class _FakeAppSettingsRepository implements AppSettingsRepository {
  List<AudioSource> _bells = [];

  @override
  Future<List<AudioSource>> loadCustomBells() async => List.from(_bells);

  @override
  Future<void> saveCustomBells(List<AudioSource> bells) async {
    _bells = List.from(bells);
  }
}
