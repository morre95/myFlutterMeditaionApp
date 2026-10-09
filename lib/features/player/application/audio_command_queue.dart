import 'dart:async';

/// Native mutation sequences must settle before a later Stop can finish.
/// Source discovery stays outside this queue so it can be superseded promptly.
class AudioCommandQueue {
  Future<void> _pending = Future<void>.value();

  Future<void> run(
    Future<void> Function() action, {
    bool Function()? canRun,
  }) async {
    final previous = _pending;
    final finished = Completer<void>();
    _pending = finished.future;
    await previous;
    try {
      if (canRun?.call() ?? true) await action();
    } finally {
      finished.complete();
    }
  }

  Future<void> disposePlayer({
    required Future<void> Function() stop,
    required void Function() dispose,
  }) => run(() async {
    // Adapter disposal may discard its native Future; await silence first.
    await stop();
    dispose();
  });
}
