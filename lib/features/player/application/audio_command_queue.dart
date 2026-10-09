import 'dart:async';

import 'package:flutter/foundation.dart';

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
    required FutureOr<void> Function() dispose,
  }) => run(() async {
    try {
      await stop();
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Audio Stop failed during teardown (${error.runtimeType}); '
          'attempting native disposal.',
        );
      }
    } finally {
      // Successful native disposal establishes silence even if Stop failed.
      await dispose();
    }
  });
}
