import 'dart:async';

/// Native mutation sequences must settle before a later Stop can finish.
/// Source discovery stays outside this queue so it can be superseded promptly.
class AudioCommandQueue {
  Future<void> _pending = Future<void>.value();
  int _commandCount = 0;

  Future<void> run(
    Future<void> Function() action, {
    bool Function()? canRun,
  }) async {
    final previous = _pending;
    final finished = Completer<void>();
    _pending = finished.future;
    _commandCount++;
    await previous;
    try {
      if (canRun?.call() ?? true) await action();
    } finally {
      _commandCount--;
      finished.complete();
    }
  }

  Future<void> disposePlayer(void Function() dispose) {
    if (_commandCount == 0) {
      dispose();
      return Future<void>.value();
    }
    return run(() async => dispose());
  }
}
