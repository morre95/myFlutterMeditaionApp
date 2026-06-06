import '../../../../shared/domain/audio_source.dart';

/// A folder entry returned when browsing pCloud.
class PCloudFolder {
  const PCloudFolder({required this.id, required this.name});

  final int id;
  final String name;
}

/// The browsable contents of a pCloud folder: sub-folders plus audio files
/// (already mapped to [AudioSource]s, with non-audio files filtered out).
class PCloudListing {
  const PCloudListing({required this.folders, required this.audioFiles});

  final List<PCloudFolder> folders;
  final List<AudioSource> audioFiles;
}
