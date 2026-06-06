import '../../../shared/domain/audio_source.dart';

class BellSelection {
  const BellSelection.builtIn(this.name) : source = null;

  const BellSelection.custom(this.source) : name = null;

  factory BellSelection.fromJson(Map<String, dynamic> json) {
    final source = json['source'];
    if (source != null) {
      return BellSelection.custom(
        AudioSource.fromJson(source as Map<String, dynamic>),
      );
    }
    return BellSelection.builtIn(json['name'] as String);
  }

  final String? name;
  final AudioSource? source;

  bool get isCustom => source != null;

  String get displayName => source?.displayName ?? name ?? 'Bell';

  Map<String, dynamic> toJson() => {
    if (source != null) 'source': source!.toJson() else 'name': name,
  };
}

class BuiltInBell {
  const BuiltInBell({
    required this.id,
    required this.label,
    required this.assetPath,
  });

  final String id;
  final String label;
  final String assetPath;

  BellSelection toSelection() => BellSelection.builtIn(id);
}

const builtInBells = <BuiltInBell>[
  BuiltInBell(id: 'bell_1', label: 'Bell 1', assetPath: 'bells/bell_1.mp3'),
  BuiltInBell(id: 'bell_2', label: 'Bell 2', assetPath: 'bells/bell_2.mp3'),
  BuiltInBell(id: 'bell_3', label: 'Bell 3', assetPath: 'bells/bell_3.mp3'),
  BuiltInBell(id: 'bell_4', label: 'Bell 4', assetPath: 'bells/bell_4.mp3'),
];
