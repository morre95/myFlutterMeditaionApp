import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device screen awake while a timer session is active.
///
/// A meditation timer relies on an in-process [Timer], which the OS suspends
/// when the screen locks or the screen saver activates. Holding a wakelock for
/// the duration of a running session prevents the countdown from freezing.
/// Kept behind an interface so the platform plugin can be faked in tests.
abstract interface class WakeLock {
  Future<void> enable();

  Future<void> disable();
}

class WakelockPlusWakeLock implements WakeLock {
  const WakelockPlusWakeLock();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}
