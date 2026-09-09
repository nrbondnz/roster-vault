import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Task 9 — Risk Register row 1 ("Device clock set backward to extend a
/// token's life"). The mitigation is a persisted high-water-mark: the
/// highest *server-attested* timestamp this device has ever actually seen,
/// via a signature-verified token's own `iat` claim (never the device's own
/// clock -- that's precisely the thing under suspicion here). Sign-in is
/// refused if the device's current wall clock ever reads earlier than that
/// stored mark, since the only way that can happen honestly is the clock
/// having been moved backward (time doesn't otherwise run in reverse).
///
/// Deliberately does not attempt to detect a clock moved *forward* -- that
/// shortens a token's useful life rather than extending it, so it isn't the
/// threat this row of the Risk Register names.
class ClockIntegrityService {
  ClockIntegrityService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const _highWaterMarkKey = 'roster_vault_clock_high_water_mark_epoch_seconds';

  /// Records [serverEpochSeconds] as seen, raising the stored high-water
  /// mark if it's newer than what's already there. Never lowers it --
  /// an older-looking successful verification (a stale-but-still-valid
  /// cached token, say) must not erase a later mark already recorded.
  Future<void> recordObservedServerTime(int serverEpochSeconds) async {
    final current = await _readHighWaterMark();
    if (current == null || serverEpochSeconds > current) {
      await _secureStorage.write(key: _highWaterMarkKey, value: serverEpochSeconds.toString());
    }
  }

  /// True if the device's current clock reads earlier than the highest
  /// server-attested timestamp this device has previously recorded --
  /// i.e. the clock has been rolled backward since then. False (not
  /// rolled back) if no high-water mark has ever been recorded yet, since
  /// there is nothing to compare against on a device's very first
  /// successful verification.
  Future<bool> isClockRolledBack({DateTime? now}) async {
    final highWaterMark = await _readHighWaterMark();
    if (highWaterMark == null) return false;
    final currentEpochSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return currentEpochSeconds < highWaterMark;
  }

  Future<int?> _readHighWaterMark() async {
    final stored = await _secureStorage.read(key: _highWaterMarkKey);
    return stored == null ? null : int.parse(stored);
  }
}
