import '../../../shared/domain/audio_source.dart';

class QueueEntry {
  const QueueEntry({
    required this.id,
    required this.source,
    required this.addedAt,
  });

  final String id;
  final AudioSource source;
  final DateTime addedAt;
}
