import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Task 9 — Risk Register row 2 ("Device lost or stolen inside the TTL
/// window"): "lockout after repeated failed attempts, tracked per profile
/// so one person's lockout doesn't affect another's." Tracked entirely
/// keyed by userId so it composes correctly with the roster's multi-profile
/// model from Task 7 -- locking one person out must never touch another
/// profile's own attempt count or lockout state.
///
/// [lockoutThreshold] and [lockoutDuration] are policy knobs, not fixed by
/// the architecture -- same treatment as the token TTL (Task 4a's notes).
/// A short duration is used here (60s, not e.g. 15 minutes) specifically so
/// the lockout and its expiry can both be demonstrated live within a normal
/// testing session; a real deployment would likely want a longer window
/// and/or exponential backoff, which is a product decision, not a technical
/// constraint of this mechanism.
class PinLockoutService {
  PinLockoutService({
    FlutterSecureStorage? secureStorage,
    this.lockoutThreshold = 5,
    this.lockoutDuration = const Duration(seconds: 60),
    DateTime Function()? clock,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _clock = clock ?? DateTime.now;

  final FlutterSecureStorage _secureStorage;
  final int lockoutThreshold;
  final Duration lockoutDuration;
  final DateTime Function() _clock;

  static String _failCountKey(String userId) => 'roster_vault_pin_fail_count_$userId';
  static String _lockedUntilKey(String userId) => 'roster_vault_pin_locked_until_$userId';

  /// If this profile is currently locked out, the moment the lockout lifts.
  /// Null if not locked out (either never failed enough times, or a
  /// previous lockout has already expired).
  Future<DateTime?> lockedUntil(String userId) async {
    final stored = await _secureStorage.read(key: _lockedUntilKey(userId));
    if (stored == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(int.parse(stored));
    if (_clock().isAfter(until)) {
      // Lockout has naturally expired -- clean up so future reads are cheap
      // and don't need to re-derive "expired" every time.
      await _secureStorage.delete(key: _lockedUntilKey(userId));
      await _secureStorage.delete(key: _failCountKey(userId));
      return null;
    }
    return until;
  }

  /// Records one failed PIN attempt for [userId]. Once [lockoutThreshold]
  /// consecutive failures have accumulated, sets a lockout that expires
  /// after [lockoutDuration]. Returns the resulting lockout expiry, or null
  /// if this failure didn't (yet) trigger a lockout.
  Future<DateTime?> recordFailure(String userId) async {
    final current = await _secureStorage.read(key: _failCountKey(userId));
    final count = (current == null ? 0 : int.parse(current)) + 1;
    await _secureStorage.write(key: _failCountKey(userId), value: count.toString());
    if (count >= lockoutThreshold) {
      final until = _clock().add(lockoutDuration);
      await _secureStorage.write(key: _lockedUntilKey(userId), value: until.millisecondsSinceEpoch.toString());
      return until;
    }
    return null;
  }

  /// Clears this profile's failure count and any lockout -- called after a
  /// correct PIN, so a genuine owner regaining access isn't left with a
  /// stale near-lockout count from earlier mistaken attempts.
  Future<void> reset(String userId) async {
    await _secureStorage.delete(key: _failCountKey(userId));
    await _secureStorage.delete(key: _lockedUntilKey(userId));
  }
}
