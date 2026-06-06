import '../../../../shared/domain/audio_source.dart';
import '../../../player/application/playback_source_resolver.dart';
import 'pcloud_service.dart';

/// Resolves pCloud sources to fresh streaming URLs and delegates everything
/// else (local files) to a wrapped resolver.
class PCloudPlaybackSourceResolver implements PlaybackSourceResolver {
  PCloudPlaybackSourceResolver({
    required PCloudService service,
    PlaybackSourceResolver? localResolver,
  }) : _service = service,
       _local = localResolver ?? const LocalPlaybackSourceResolver();

  final PCloudService _service;
  final PlaybackSourceResolver _local;

  @override
  Future<PlayableMedia> resolve(AudioSource source) async {
    if (source.kind == AudioSourceKind.pCloud) {
      final url = await _service.getFileLink(source.reference);
      return PlayableMedia.url(url);
    }
    return _local.resolve(source);
  }
}
