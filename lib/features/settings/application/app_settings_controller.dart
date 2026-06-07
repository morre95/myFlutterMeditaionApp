import 'package:flutter/foundation.dart';

import '../../../shared/domain/audio_source.dart';
import '../../timer/domain/bell_selection.dart';
import '../infrastructure/shared_preferences_app_settings_repository.dart';

/// Holds shared user preferences: the library of custom timer bells (local
/// audio files the user picked) and which preinstalled bells the user has
/// disabled. Both feed the timer's bell picker.
class AppSettingsController extends ChangeNotifier {
  AppSettingsController({required AppSettingsRepository repository})
    : _repository = repository;

  final AppSettingsRepository _repository;

  List<AudioSource> _customBells = [];
  Set<String> _disabledBuiltInBellIds = {};

  List<AudioSource> get customBells =>
      List<AudioSource>.unmodifiable(_customBells);

  /// Preinstalled bells the user has not disabled, in catalog order.
  List<BuiltInBell> get enabledBuiltInBells => builtInBells
      .where((b) => !_disabledBuiltInBellIds.contains(b.id))
      .toList();

  bool isBuiltInBellEnabled(String id) =>
      !_disabledBuiltInBellIds.contains(id);

  Future<void> load() async {
    _customBells = await _repository.loadCustomBells();
    _disabledBuiltInBellIds = await _repository.loadDisabledBuiltInBells();
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

  /// Disables a preinstalled bell so it stops appearing as a timer option. The
  /// bell is not deleted and can be re-enabled later. Refuses to disable the
  /// last enabled bell so the timer always has an ending sound; returns whether
  /// the bell was disabled.
  Future<bool> disableBuiltInBell(String id) async {
    if (_disabledBuiltInBellIds.contains(id)) return true;
    final wouldLeaveOneEnabled = builtInBells.any(
      (b) => b.id != id && !_disabledBuiltInBellIds.contains(b.id),
    );
    if (!wouldLeaveOneEnabled) return false;
    _disabledBuiltInBellIds = {..._disabledBuiltInBellIds, id};
    await _repository.saveDisabledBuiltInBells(_disabledBuiltInBellIds);
    notifyListeners();
    return true;
  }

  Future<void> enableBuiltInBell(String id) async {
    if (!_disabledBuiltInBellIds.contains(id)) return;
    _disabledBuiltInBellIds = {..._disabledBuiltInBellIds}..remove(id);
    await _repository.saveDisabledBuiltInBells(_disabledBuiltInBellIds);
    notifyListeners();
  }
}
