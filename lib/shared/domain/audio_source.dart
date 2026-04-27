enum AudioSourceKind { localFile, pCloud, googleDrive, oneDrive, dropbox }

class AudioSource {
  const AudioSource({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.reference,
    this.duration,
  });

  final String id;
  final AudioSourceKind kind;
  final String displayName;

  /// A read-only local URI/path or cloud provider object identifier.
  final String reference;

  final Duration? duration;

  bool get isSupportedAudio {
    const supported = {'.wav', '.mp3', '.flac', '.ogg', '.m4a', '.aac'};
    final lower = displayName.toLowerCase();
    return supported.any(lower.endsWith);
  }

  AudioSource copyWith({
    String? id,
    AudioSourceKind? kind,
    String? displayName,
    String? reference,
    Duration? duration,
  }) {
    return AudioSource(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      reference: reference ?? this.reference,
      duration: duration ?? this.duration,
    );
  }
}
