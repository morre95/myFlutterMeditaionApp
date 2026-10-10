import 'package:flutter/material.dart';

import '../../../../shared/domain/audio_source.dart';
import '../../domain/bell_selection.dart';

/// Picks an ending bell from the enabled built-in bells and the custom bells.
class BellDropdown extends StatelessWidget {
  const BellDropdown({
    super.key,
    required this.selection,
    required this.builtIns,
    required this.customBells,
    required this.onChanged,
  });

  final BellSelection selection;
  final List<BuiltInBell> builtIns;
  final List<AudioSource> customBells;

  /// Null disables the picker.
  final ValueChanged<BellSelection>? onChanged;

  /// Maps [selection] to a dropdown key, falling back to the first enabled
  /// built-in bell if the selected bell was removed or disabled.
  String _currentKey() {
    final bell = selection;
    if (bell.isCustom) {
      final id = bell.source!.id;
      if (customBells.any((b) => b.id == id)) return 'custom:$id';
      return 'builtin:${builtIns.first.id}';
    }
    final name = bell.name;
    if (builtIns.any((b) => b.id == name)) return 'builtin:$name';
    return 'builtin:${builtIns.first.id}';
  }

  BellSelection? _selectionFor(String key) {
    if (key.startsWith('custom:')) {
      final id = key.substring('custom:'.length);
      for (final bell in customBells) {
        if (bell.id == id) return BellSelection.custom(bell);
      }
      return null;
    }
    return BellSelection.builtIn(key.substring('builtin:'.length));
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return DropdownButtonFormField<String>(
      initialValue: _currentKey(),
      decoration: const InputDecoration(
        labelText: 'Ending bell',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final bell in builtIns)
          DropdownMenuItem<String>(
            value: 'builtin:${bell.id}',
            child: Text(bell.label),
          ),
        for (final bell in customBells)
          DropdownMenuItem<String>(
            value: 'custom:${bell.id}',
            child: Text(bell.displayName),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (value) {
              final selection = value == null ? null : _selectionFor(value);
              if (selection != null) onChanged(selection);
            },
    );
  }
}
