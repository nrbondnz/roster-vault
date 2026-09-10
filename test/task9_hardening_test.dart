import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_vault/services/clock_integrity_service.dart';
import 'package:roster_vault/services/pin_lockout_service.dart';
import 'package:roster_vault/services/root_detection_service.dart';

/// Task 10 (traceability pass) caught that Task 9's three new services had
/// real on-device proof but zero automated coverage -- everything else in
/// this project has both. Added here rather than left as a silent gap.
/// [FakeSecureStorage] is a plain in-memory stand-in -- `FlutterSecureStorage`
/// has no platform channel wired up under `flutter test`, and these
/// services only ever call `read`/`write`/`delete` on it.
class FakeSecureStorage extends FlutterSecureStorage {
  final _store = <String, String>{};

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      _store[key];

  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    _store.remove(key);
  }
}

void main() {
  group('ClockIntegrityService', () {
    test('no high-water mark recorded yet -> not rolled back', () async {
      final service = ClockIntegrityService(secureStorage: FakeSecureStorage());
      expect(await service.isClockRolledBack(), isFalse);
    });

    test('current time before the recorded high-water mark -> rolled back', () async {
      final service = ClockIntegrityService(secureStorage: FakeSecureStorage());
      final serverNow = DateTime(2026, 9, 10);
      await service.recordObservedServerTime(serverNow.millisecondsSinceEpoch ~/ 1000);
      final rolledBackClock = DateTime(2026, 9, 8);
      expect(await service.isClockRolledBack(now: rolledBackClock), isTrue);
    });

    test('current time at or after the recorded high-water mark -> not rolled back', () async {
      final service = ClockIntegrityService(secureStorage: FakeSecureStorage());
      final serverNow = DateTime(2026, 9, 10);
      await service.recordObservedServerTime(serverNow.millisecondsSinceEpoch ~/ 1000);
      final laterClock = DateTime(2026, 9, 12);
      expect(await service.isClockRolledBack(now: laterClock), isFalse);
    });

    test('high-water mark never moves backward even from an older observation', () async {
      final service = ClockIntegrityService(secureStorage: FakeSecureStorage());
      await service.recordObservedServerTime(DateTime(2026, 9, 10).millisecondsSinceEpoch ~/ 1000);
      await service.recordObservedServerTime(DateTime(2026, 9, 5).millisecondsSinceEpoch ~/ 1000);
      expect(await service.isClockRolledBack(now: DateTime(2026, 9, 8)), isTrue);
    });
  });

  group('PinLockoutService', () {
    test('not locked out before any failures', () async {
      final service = PinLockoutService(secureStorage: FakeSecureStorage());
      expect(await service.lockedUntil('user-a'), isNull);
    });

    test('locks out after reaching the threshold, not before', () async {
      final service = PinLockoutService(secureStorage: FakeSecureStorage(), lockoutThreshold: 3);
      expect(await service.recordFailure('user-a'), isNull);
      expect(await service.recordFailure('user-a'), isNull);
      expect(await service.recordFailure('user-a'), isNotNull);
      expect(await service.lockedUntil('user-a'), isNotNull);
    });

    test('one profile locking out does not affect another', () async {
      final service = PinLockoutService(secureStorage: FakeSecureStorage(), lockoutThreshold: 1);
      await service.recordFailure('user-a');
      expect(await service.lockedUntil('user-a'), isNotNull);
      expect(await service.lockedUntil('user-b'), isNull);
    });

    test('reset clears the lockout and failure count', () async {
      final service = PinLockoutService(secureStorage: FakeSecureStorage(), lockoutThreshold: 1);
      await service.recordFailure('user-a');
      expect(await service.lockedUntil('user-a'), isNotNull);
      await service.reset('user-a');
      expect(await service.lockedUntil('user-a'), isNull);
    });

    test('a lockout whose duration has already passed is treated as expired', () async {
      var now = DateTime(2026, 9, 10, 12, 0, 0);
      final service = PinLockoutService(
        secureStorage: FakeSecureStorage(),
        lockoutThreshold: 1,
        lockoutDuration: const Duration(seconds: 60),
        clock: () => now,
      );
      await service.recordFailure('user-a');
      now = now.add(const Duration(seconds: 61));
      expect(await service.lockedUntil('user-a'), isNull);
    });
  });

  group('RootDetectionService', () {
    test('a clean test environment is not reported as compromised', () {
      // Best-effort only (see the service's own doc) -- this asserts the
      // false-negative path doesn't misfire in a normal, unmodified
      // environment, not that the check is a real security boundary. The
      // true-positive path (an actually-rooted device) remains unverified
      // on real hardware -- see the story checkpoint's Task 9/10 entries.
      const service = RootDetectionService();
      expect(service.isLikelyCompromised(), isFalse);
    });

    test('reports compromised when a checked path genuinely exists', () async {
      final tempDir = await Directory.systemTemp.createTemp('root_detection_test');
      final fakeSuFile = File('${tempDir.path}/su');
      await fakeSuFile.create();
      addTearDown(() => tempDir.delete(recursive: true));

      final service = RootDetectionService(checkPaths: [fakeSuFile.path]);
      expect(service.isLikelyCompromised(), isTrue);
    });
  });
}
