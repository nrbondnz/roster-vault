import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_vault/services/fresh_install_guard.dart';

/// Same in-memory stand-in pattern as `test/task9_hardening_test.dart`'s
/// `FakeSecureStorage`, extended with `readAll`/`deleteAll` -- the two
/// methods this class specifically needs that the Task 9 fake didn't.
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
  Future<Map<String, String>> readAll({AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      Map.of(_store);

  @override
  Future<void> deleteAll({AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    _store.clear();
  }
}

void main() {
  late Directory tempDir;
  late FakeSecureStorage storage;
  late FreshInstallGuard guard;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fresh_install_guard_test_');
    storage = FakeSecureStorage();
    guard = FreshInstallGuard(secureStorage: storage, appSupportDirectory: () async => tempDir);
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  test('genuine first-ever install -- nothing in secure storage, just creates the marker', () async {
    await guard.ensureCleanSlateOnFreshInstall();

    expect(File('${tempDir.path}/.roster_vault_installed').existsSync(), isTrue);
    expect(await storage.readAll(), isEmpty);
  });

  test('marker already present -- an ordinary relaunch -- leaves existing data untouched', () async {
    await storage.write(key: 'roster_vault_device_master_key', value: 'still-here');
    File('${tempDir.path}/.roster_vault_installed').createSync(recursive: true);

    await guard.ensureCleanSlateOnFreshInstall();

    expect(await storage.read(key: 'roster_vault_device_master_key'), 'still-here');
  });

  test('stale Keychain data with no marker -- the real iOS reinstall scenario -- gets wiped', () async {
    await storage.write(key: 'roster_vault_device_master_key', value: 'stale-from-previous-install');
    await storage.write(key: 'roster_vault_enrollment_token_user-a', value: 'stale-token');
    final partitionFile = File('${tempDir.path}/roster_vault_partition_user-a.db')..createSync();
    final unrelatedFile = File('${tempDir.path}/not_a_partition_file.txt')..createSync();

    await guard.ensureCleanSlateOnFreshInstall();

    expect(await storage.readAll(), isEmpty, reason: 'stale Keychain entries from the previous install must be gone');
    expect(partitionFile.existsSync(), isFalse, reason: 'a stale encrypted partition file must be gone too');
    expect(unrelatedFile.existsSync(), isTrue, reason: 'only roster_vault_partition_* files are in scope -- nothing else should be touched');
    expect(File('${tempDir.path}/.roster_vault_installed').existsSync(), isTrue);
  });

  test('running it twice in a row -- second call is a no-op, not a second wipe', () async {
    await storage.write(key: 'roster_vault_device_master_key', value: 'stale-from-previous-install');
    await guard.ensureCleanSlateOnFreshInstall();

    // A real second app launch would now see the marker and skip
    // straight past -- confirm data written *after* the first run
    // (i.e. this device's own real enrollment) survives a second call.
    await storage.write(key: 'roster_vault_device_master_key', value: 'this-installs-own-real-key');
    await guard.ensureCleanSlateOnFreshInstall();

    expect(await storage.read(key: 'roster_vault_device_master_key'), 'this-installs-own-real-key');
  });
}
