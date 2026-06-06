import '../../../shared/domain/audio_source.dart';

enum PlayableMediaKind { file, url }

/// A resolved, immediately-playable locator for an [AudioSource].
///
/// Local files resolve to a device path ([PlayableMediaKind.file]); remote
/// sources resolve to a temporary streaming URL ([PlayableMediaKind.url]).
class PlayableMedia {
  const PlayableMedia.file(this.locator) : kind = PlayableMediaKind.file;
  const PlayableMedia.url(this.locator) : kind = PlayableMediaKind.url;

  final PlayableMediaKind kind;
  final String locator;
}

class UnsupportedSourceException implements Exception {
  const UnsupportedSourceException(this.kind);

  final AudioSourceKind kind;

  @override
  String toString() => 'Unsupported audio source: ${kind.name}';
}

/// Turns an [AudioSource] into a [PlayableMedia] the audio player can load.
abstract interface class PlaybackSourceResolver {
  Future<PlayableMedia> resolve(AudioSource source);
}

/// Resolves local-file sources only. Remote kinds throw
/// [UnsupportedSourceException]; a cloud-aware resolver wraps this one.
class LocalPlaybackSourceResolver implements PlaybackSourceResolver {
  const LocalPlaybackSourceResolver();

  @override
  Future<PlayableMedia> resolve(AudioSource source) async {
    switch (source.kind) {
      case AudioSourceKind.localFile:
        return PlayableMedia.file(source.reference);
      case AudioSourceKind.pCloud:
      case AudioSourceKind.googleDrive:
      case AudioSourceKind.oneDrive:
      case AudioSourceKind.dropbox:
        throw UnsupportedSourceException(source.kind);
    }
  }
}
