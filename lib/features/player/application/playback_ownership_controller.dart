import 'dart:async';

/// Serializes mode changes and stops the previous mode before starting another.
/// Screens can come and go without releasing the application's music owner.
class PlaybackOwnershipController {
  Object? _activeOwner;
  Future<void> Function()? _deactivate;
  Future<void> _pending = Future<void>.value();

  Object? get activeOwner => _activeOwner;

  Future<void> run({
    required Object owner,
    required Future<void> Function() deactivate,
    required Future<void> Function() action,
    required bool Function() canRun,
  }) async {
    final previous = _pending;
    final finished = Completer<void>();
    _pending = finished.future;
    await previous;
    Future<void>? pendingAction;
    try {
      if (!canRun()) return;
      if (!identical(_activeOwner, owner)) {
        await _deactivate?.call();
        if (!canRun()) return;
        _activeOwner = owner;
        _deactivate = deactivate;
      }
      pendingAction = action();
    } finally {
      // Cloud resolution belongs to the owner, not the handoff lock.
      finished.complete();
    }
    await pendingAction;
  }

  /// Disposed owners already stop their resources; drop their retained callback.
  void forget(Object owner) {
    if (!identical(_activeOwner, owner)) return;
    _activeOwner = null;
    _deactivate = null;
  }
}
