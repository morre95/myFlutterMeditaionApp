import 'package:flutter_test/flutter_test.dart';
import 'package:my_meditation_app/features/timer/domain/bell_selection.dart';
import 'package:my_meditation_app/shared/domain/audio_source.dart';

void main() {
  group('BellSelection JSON', () {
    test('round-trips a built-in bell', () {
      const selection = BellSelection.builtIn('bell_2');

      final restored = BellSelection.fromJson(selection.toJson());

      expect(restored.isCustom, isFalse);
      expect(restored.name, 'bell_2');
    });

    test('round-trips a custom bell with its audio source', () {
      const source = AudioSource(
        id: 'local:/bells/gong.mp3',
        kind: AudioSourceKind.localFile,
        displayName: 'gong.mp3',
        reference: '/bells/gong.mp3',
      );
      const selection = BellSelection.custom(source);

      final restored = BellSelection.fromJson(selection.toJson());

      expect(restored.isCustom, isTrue);
      expect(restored.source?.reference, '/bells/gong.mp3');
      expect(restored.displayName, 'gong.mp3');
    });
  });
}
