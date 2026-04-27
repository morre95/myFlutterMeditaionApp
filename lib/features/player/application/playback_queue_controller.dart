import 'package:flutter/foundation.dart';

import '../../../shared/domain/audio_source.dart';
import '../domain/queue_entry.dart';

class PlaybackQueueController extends ChangeNotifier {
  final List<QueueEntry> _entries = <QueueEntry>[];
  int _nextEntryId = 0;

  List<QueueEntry> get entries => List<QueueEntry>.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  QueueEntry add(AudioSource source) {
    final entry = _createEntry(source);
    _entries.add(entry);
    notifyListeners();
    return entry;
  }

  List<QueueEntry> addAll(Iterable<AudioSource> sources) {
    final newEntries = sources.map(_createEntry).toList(growable: false);
    if (newEntries.isEmpty) {
      return const <QueueEntry>[];
    }

    _entries.addAll(newEntries);
    notifyListeners();
    return newEntries;
  }

  QueueEntry? entryById(String entryId) {
    for (final entry in _entries) {
      if (entry.id == entryId) {
        return entry;
      }
    }

    return null;
  }

  QueueEntry _createEntry(AudioSource source) {
    final entry = QueueEntry(
      id: 'queue-entry-${_nextEntryId++}',
      source: source,
      addedAt: DateTime.now(),
    );

    return entry;
  }

  void remove(String entryId) {
    final initialLength = _entries.length;
    _entries.removeWhere((entry) => entry.id == entryId);

    if (_entries.length != initialLength) {
      notifyListeners();
    }
  }

  void reorder({required int oldIndex, required int newIndex}) {
    if (oldIndex < 0 || oldIndex >= _entries.length) {
      throw RangeError.index(oldIndex, _entries, 'oldIndex');
    }
    if (newIndex < 0 || newIndex > _entries.length) {
      throw RangeError.index(newIndex, _entries, 'newIndex');
    }

    final entry = _entries.removeAt(oldIndex);
    final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _entries.insert(adjustedIndex, entry);
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) {
      return;
    }

    _entries.clear();
    notifyListeners();
  }
}
