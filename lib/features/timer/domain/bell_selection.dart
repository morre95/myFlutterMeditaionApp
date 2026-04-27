import '../../../shared/domain/audio_source.dart';

class BellSelection {
  const BellSelection.builtIn(this.name) : source = null;

  const BellSelection.custom(this.source) : name = null;

  final String? name;
  final AudioSource? source;

  bool get isCustom => source != null;

  String get displayName => source?.displayName ?? name ?? 'Bell';
}
