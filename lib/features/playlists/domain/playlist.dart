import '../../../shared/domain/audio_source.dart';

class PlaylistTrack {
  const PlaylistTrack({required this.id, required this.source});

  factory PlaylistTrack.fromJson(Map<String, dynamic> json) {
    return PlaylistTrack(
      id: json['id'] as String,
      source: AudioSource.fromJson(json['source'] as Map<String, dynamic>),
    );
  }

  final String id;
  final AudioSource source;

  Map<String, dynamic> toJson() => {'id': id, 'source': source.toJson()};
}

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.tracks,
    required this.createdAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>;
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      tracks: rawTracks
          .map((t) => PlaylistTrack.fromJson(t as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String name;
  final List<PlaylistTrack> tracks;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  Playlist copyWith({String? name, List<PlaylistTrack>? tracks}) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt,
    );
  }
}
