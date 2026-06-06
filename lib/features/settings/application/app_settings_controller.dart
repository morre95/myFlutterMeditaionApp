import 'package:flutter/foundation.dart';

import '../../../shared/domain/audio_source.dart';
import '../infrastructure/shared_preferences_app_settings_repository.dart';

/// Holds shared user preferences. Currently the library of custom timer bells
/// (local audio files the user picked) that should appear in the timer's bell
/// picker.
class AppSettingsController extends ChangeNotifier {
  AppSettingsController({required AppSettingsRepository repository})
    : _repository = repository;

  final AppSettingsRepository _repository;

  List<AudioSource> _customBells = [];

  List<AudioSource> get customBells => List<AudioSource>.unmodifiable(_customBells);

  Future<void> load() async {
    _customBells = await _repository.loadCustomBells();
    notifyListeners();
  }

  Future<void> addCustomBell(AudioSource bell) async {
    if (_customBells.any((b) => b.id == bell.id)) return;
    _customBells = [..._customBells, bell];
    await _repository.saveCustomBells(_customBells);
    notifyListeners();
  }

  Future<void> removeCustomBell(String id) async {
    _customBells = _customBells.where((b) => b.id != id).toList();
    await _repository.saveCustomBells(_customBells);
    notifyListeners();
  }
}
