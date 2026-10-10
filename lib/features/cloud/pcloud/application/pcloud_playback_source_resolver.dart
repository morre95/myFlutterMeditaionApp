import '../../../../shared/domain/audio_source.dart';
import '../../../player/application/playback_source_resolver.dart';
import 'pcloud_download_controller.dart';
import 'pcloud_service.dart';

/// Resolves pCloud sources to their downloaded copy when one is available
/// offline, otherwise to a fresh streaming URL. Everything else (local files)
/// is delegated to a wrapped resolver.
class PCloudPlaybackSourceResolver implements PlaybackSourceResolver {
  PCloudPlaybackSourceResolver({
    required PCloudService service,
    required PCloudDownloadController downloads,
    PlaybackSourceResolver? localResolver,
  }) : _service = service,
       _downloads = downloads,
       _local = localResolver ?? const LocalPlaybackSourceResolver();

  final PCloudService _service;
  final PCloudDownloadController _downloads;
  final PlaybackSourceResolver _local;

  @override
  Future<PlayableMedia> resolve(AudioSource source) async {
    if (source.kind == AudioSourceKind.pCloud) {
      final copy = _downloads.offlineCopyOf(source);
      if (copy != null) return PlayableMedia.file(copy.path);
      final url = await _service.getFileLink(source.reference);
      return PlayableMedia.url(url);
    }
    return _local.resolve(source);
  }
}
