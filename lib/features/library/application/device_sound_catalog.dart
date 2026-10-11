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
}
