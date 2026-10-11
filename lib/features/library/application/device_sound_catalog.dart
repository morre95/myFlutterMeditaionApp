import '../../../shared/domain/audio_source.dart';
import '../../cloud/pcloud/application/pcloud_download_controller.dart';
import 'local_audio_library.dart';

/// Sounds stored on this device: imported copies and downloaded pCloud
/// copies. These are the sounds usable in Offline mode.
class DeviceSoundCatalog {
  DeviceSoundCatalog({
    required LocalAudioLibrary library,
    required PCloudDownloadController downloads,
    required bool Function(AudioSource sound) isInActiveSession,
  }) : _library = library,
       _downloads = downloads,
       _isInActiveSession = isInActiveSession;

  final LocalAudioLibrary _library;
  final PCloudDownloadController _downloads;
  final bool Function(AudioSource sound) _isInActiveSession;

  /// Complete device copies, each with its `storedSize`; a download whose
  /// audio vanished is left out.
  Future<List<AudioSource>> load() async {
    final imports = await _library.loadSounds();
    final downloads = <AudioSource>[];
    for (final copy in _downloads.offlineCopies) {
      final verified = await _downloads.verifiedCopyOf(copy.source);
      if (verified != null) downloads.add(verified.source);
    }
    return [...imports, ...downloads];
  }

  /// Whether [sound] can play in Offline mode: a device file, or a pCloud
  /// sound with a downloaded copy. Playback still verifies the copy on disk.
  bool isAvailableOffline(AudioSource sound) => switch (sound.kind) {
    AudioSourceKind.localFile => true,
    AudioSourceKind.pCloud => _downloads.offlineCopyOf(sound) != null,
    _ => false,
  };

  /// Deletes the device copy of [sound] without touching its original file
  /// or cloud object. A sound used by an active session is kept.
  Future<void> remove(AudioSource sound) async {
    if (_isInActiveSession(sound)) throw SoundInUseException(sound);
    if (sound.kind == AudioSourceKind.pCloud) {
      await _downloads.remove(sound);
    } else {
      await _library.removeSound(sound);
    }
  }
}

/// [sound] cannot be removed while a session plays it.
class SoundInUseException implements Exception {
  const SoundInUseException(this.sound);

  final AudioSource sound;

  String get message =>
      '${sound.displayName} is playing in an active session. '
      'End the session before removing it.';

  @override
  String toString() => message;
}
