enum AudioSourceKind { localFile, pCloud, googleDrive, oneDrive, dropbox }

AudioSourceKind _kindFromJson(String value) {
  return AudioSourceKind.values.firstWhere(
    (k) => k.name == value,
    orElse: () => AudioSourceKind.localFile,
  );
}

class AudioSource {
  const AudioSource({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.reference,
    this.duration,
    this.storedSize,
  });

  factory AudioSource.fromJson(Map<String, dynamic> json) {
    final durationMs = json['durationMs'] as int?;
    return AudioSource(
      id: json['id'] as String,
      kind: _kindFromJson(json['kind'] as String),
      displayName: json['displayName'] as String,
      reference: json['reference'] as String,
      duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
      storedSize: json['storedSize'] as int?,
    );
  }

  final String id;
  final AudioSourceKind kind;
  final String displayName;

  /// A read-only local URI/path or cloud provider object identifier.
  final String reference;

  final Duration? duration;

  /// Bytes in a completed app-owned copy; absent for legacy external sources.
  final int? storedSize;

  bool get isSupportedAudio {
    const supported = {'.wav', '.mp3', '.flac', '.ogg', '.m4a', '.aac'};
    final lower = displayName.toLowerCase();
    return supported.any(lower.endsWith);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'displayName': displayName,
      'reference': reference,
      if (duration != null) 'durationMs': duration!.inMilliseconds,
      if (storedSize != null) 'storedSize': storedSize,
    };
  }

  AudioSource copyWith({
    String? id,
    AudioSourceKind? kind,
    String? displayName,
    String? reference,
    Duration? duration,
    int? storedSize,
  }) {
    return AudioSource(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      reference: reference ?? this.reference,
      duration: duration ?? this.duration,
      storedSize: storedSize ?? this.storedSize,
    );
  }
}
