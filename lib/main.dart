import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'screens/login_screen.dart';
import 'services/device_identity_service.dart';
import 'services/encrypted_partition_store.dart';
import 'services/enrollment_service.dart';
import 'services/issuer_public_key.dart';
import 'services/local_unlock_service.dart';
import 'services/offline_verifier.dart';
import 'services/token_verifier.dart';
import 'services/user_identity_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RosterVaultApp());
}

class RosterVaultApp extends StatelessWidget {
  const RosterVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roster Vault',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const _AuthGate(),
    );
  }
}

/// Task 4b — configures Amplify once, then routes to [LoginScreen] or
/// straight to [DeviceDebugScreen] depending on whether a Cognito session
/// already exists (e.g. after a hot restart). The one online step in the
/// whole system (docs/roster-vault/Architecture/Enrollment Flow.md step 1)
/// happens in [LoginScreen]; everything downstream of a successful sign-in
/// is what Task 4c (enrollment) and beyond build on.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

enum _AuthGateStatus { loading, signedOut, signedIn, error }

class _AuthGateState extends State<_AuthGate> {
  _AuthGateStatus _status = _AuthGateStatus.loading;
  AuthUser? _user;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (!Amplify.isConfigured) {
        final configJson = await rootBundle.loadString('amplify_outputs.json');
        // Sanity-check it parses before handing it to Amplify, so a missing
        // or malformed amplify_outputs.json fails with a clear message
        // instead of an opaque Amplify plugin error.
        jsonDecode(configJson);
        await Amplify.addPlugins([AmplifyAuthCognito()]);
        await Amplify.configure(configJson);
      }
      final user = await Amplify.Auth.getCurrentUser();
      setState(() {
        _user = user;
        _status = _AuthGateStatus.signedIn;
      });
    } on SignedOutException {
      setState(() => _status = _AuthGateStatus.signedOut);
    } catch (e) {
      setState(() {
        _errorText = 'Amplify configuration failed: $e';
        _status = _AuthGateStatus.error;
      });
    }
  }

  void _onSignedIn(AuthUser user) {
    setState(() {
      _user = user;
      _status = _AuthGateStatus.signedIn;
    });
  }

  /// Task 6 — needed to actually switch between two enrolled profiles on
  /// this device for the cross-profile isolation demonstration (not part
  /// of Task 7's real roster/fast-switch UI, which replaces this whole
  /// debug screen -- just enough to prove the isolation claim now).
  Future<void> _onSignedOut() async {
    await Amplify.Auth.signOut();
    setState(() => _status = _AuthGateStatus.signedOut);
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _AuthGateStatus.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _AuthGateStatus.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_errorText ?? 'Unknown error', style: const TextStyle(color: Colors.red)),
            ),
          ),
        );
      case _AuthGateStatus.signedOut:
        return LoginScreen(onSignedIn: _onSignedIn);
      case _AuthGateStatus.signedIn:
        return DeviceDebugScreen(
          deviceIdentityService: DeviceIdentityService(),
          signedInUser: _user,
          onSignedOut: _onSignedOut,
        );
    }
  }
}

/// Development-only screen. Shows this device's identity material so it can
/// be inspected during Task 3 (device keypair generation) and beyond.
/// Never shown in a release build's normal flow — the real entry point is
/// the roster screen (Task 7).
class DeviceDebugScreen extends StatefulWidget {
  const DeviceDebugScreen({super.key, required this.deviceIdentityService, this.signedInUser, this.onSignedOut});

  final DeviceIdentityService deviceIdentityService;

  /// Task 4b — set once Cognito sign-in (LoginScreen) succeeds. Displayed
  /// so the on-screen authenticated state is actually visible, not just
  /// inferred from the fact that this screen is showing at all.
  final AuthUser? signedInUser;

  /// Task 6 — lets a second person sign in on the same device, to
  /// demonstrate cross-profile isolation for real rather than with only
  /// one profile ever enrolled.
  final Future<void> Function()? onSignedOut;

  @override
  State<DeviceDebugScreen> createState() => _DeviceDebugScreenState();
}

class _DeviceDebugScreenState extends State<DeviceDebugScreen> {
  late final Future<DeviceIdentity> _deviceIdentity;
  final _userIdentityService = UserIdentityService();
  final _enrollmentService = EnrollmentService();
  final _tokenVerifier = const TokenVerifier();

  bool _isEnrolling = false;
  String? _enrollError;
  EnrollmentResult? _enrollmentResult;
  VerifiedTokenClaims? _verifiedClaims;

  final _offlineVerifier = const OfflineVerifier();
  bool _isSigningInOffline = false;
  String? _offlineSignInError;
  OfflineVerificationResult? _offlineSignInResult;

  bool _isTestingStorage = false;
  String? _storageTestResult;

  final _localUnlockService = LocalUnlockService();
  final _pinController = TextEditingController();
  bool _isUnlocking = false;
  String? _unlockResult;
  String? _unlockError;
  late Future<bool> _pinIsSetUp;

  @override
  void initState() {
    super.initState();
    _deviceIdentity = widget.deviceIdentityService.ensureDeviceIdentity().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException(
        'Device key generation did not respond in time. On Windows this plugin falls back to '
        'RSA via Windows Hello/TPM, which requires a Windows Hello PIN to be configured on this '
        'machine — this platform is a dev convenience, not the deployment target (Android/iOS).',
      ),
    );
    _pinIsSetUp = widget.signedInUser == null
        ? Future.value(false)
        : _localUnlockService.isSetUp(widget.signedInUser!.userId);
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  /// Task 4c — generate this person's per-device keypair, call the `enroll`
  /// mutation (Task 4a) with it and this device's already-established
  /// identity (Task 3), then verify the returned token's signature locally
  /// against the issuer public key baked in at build time (Task 4a). Purely
  /// a debug-view trigger for now, per the story checkpoint's Task 4c scope
  /// -- the real roster/enrollment UI is Task 7.
  Future<void> _enroll(DeviceIdentity deviceIdentity) async {
    final user = widget.signedInUser;
    if (user == null) return;
    setState(() {
      _isEnrolling = true;
      _enrollError = null;
    });
    try {
      final userPubKey = await _userIdentityService.ensureUserKeyPair(user.userId).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'User key generation did not respond in time. On Windows, key creation can trigger a '
          'Windows Hello consent prompt (CredentialUIBroker) with no visible dialog if no Windows '
          'Hello PIN is configured on this machine -- it hangs rather than failing. Same platform '
          'caveat as the device key (see DeviceDebugScreen.initState): a dev convenience, not the '
          'deployment target.',
        ),
      );
      final result = await _enrollmentService.enroll(
        deviceId: deviceIdentity.deviceId,
        devicePubKey: deviceIdentity.publicKeyPem,
        userPubKey: userPubKey,
      );
      final verified = await _tokenVerifier.verify(result.token, issuerPublicKeyPem: issuerPublicKeyPem);
      setState(() {
        _enrollmentResult = result;
        _verifiedClaims = verified;
      });
    } catch (e) {
      setState(() => _enrollError = 'Enrollment failed: $e');
    } finally {
      if (mounted) setState(() => _isEnrolling = false);
    }
  }

  /// Task 5 — the actual hard requirement. Runs [OfflineVerifier] against
  /// whatever token is already stored on this device from Task 4c's
  /// enrollment flow -- makes no network call of any kind (see
  /// [OfflineVerifier]'s own doc comment on why that's true by
  /// construction, not just by review). See the story checkpoint's Task 5
  /// entry for exactly what this has and hasn't been demonstrated with on
  /// this particular machine.
  Future<void> _signInOffline(DeviceIdentity deviceIdentity) async {
    final user = widget.signedInUser;
    if (user == null) return;
    setState(() {
      _isSigningInOffline = true;
      _offlineSignInError = null;
      _offlineSignInResult = null;
    });
    try {
      final storedToken = await _enrollmentService.storedToken(user.userId);
      if (storedToken == null) {
        setState(() => _offlineSignInError = 'No enrolled profile found on this device for this person yet — enroll first.');
        return;
      }
      final knownEpoch = await _enrollmentService.knownEpoch(user.userId) ?? 0;

      final result = await _offlineVerifier.verify(
        token: storedToken,
        issuerPublicKeyPem: issuerPublicKeyPem,
        expectedDeviceId: deviceIdentity.deviceId,
        currentKnownEpoch: knownEpoch,
        userPublicKeyPem: await _userIdentityService.ensureUserKeyPair(user.userId).timeout(const Duration(seconds: 15)),
        signChallenge: _productionChallengeSigner(user.userId),
      );
      setState(() => _offlineSignInResult = result);
    } catch (e) {
      setState(() => _offlineSignInError = 'Offline sign-in check failed: $e');
    } finally {
      if (mounted) setState(() => _isSigningInOffline = false);
    }
  }

  /// Task 6 — proves real encryption is active on *this* device, the same
  /// way Task 5's airplane-mode test proved offline verification: not by
  /// inspecting code, by observing it. Writes real data through
  /// [EncryptedPartitionStore] with one key, confirms the raw file bytes on
  /// disk are neither the plaintext SQLite header nor the plaintext value,
  /// confirms a wrong key fails to read it, then confirms the right key
  /// still can. See docs/roster-vault/Troubleshooting/Known Issues.md and
  /// the story checkpoint's Task 6 entry for why this was ever in doubt.
  Future<void> _testEncryptedStorage() async {
    setState(() {
      _isTestingStorage = true;
      _storageTestResult = null;
    });
    const store = EncryptedPartitionStore();
    final dir = await Directory.systemTemp.createTemp('roster_vault_storage_test_');
    final path = '${dir.path}/test.db';
    const rightKey = [
      0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55,
      0x66, 0x77, 0x88, 0x99, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0x00, 0x11,
    ];
    const wrongKey = [
      0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
      0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    ];
    const secret = 'this is secret plaintext data';
    try {
      final db1 = store.open(dbPath: path, partitionKey: rightKey);
      db1.execute("CREATE TABLE IF NOT EXISTS t (k TEXT PRIMARY KEY, v TEXT NOT NULL)");
      db1.execute("INSERT INTO t VALUES ('hello', '$secret')");
      db1.close();

      final bytes = await File(path).readAsBytes();
      final headerIsPlaintext = String.fromCharCodes(bytes.take(16)).startsWith('SQLite format 3');
      final containsSecret = String.fromCharCodes(bytes).contains(secret);

      var wrongKeyRejected = false;
      try {
        store.open(dbPath: path, partitionKey: wrongKey);
      } on WrongPartitionKeyException {
        wrongKeyRejected = true;
      }

      final db2 = store.open(dbPath: path, partitionKey: rightKey);
      final rows = db2.select("SELECT v FROM t WHERE k = 'hello'");
      db2.close();
      final rightKeyWorked = rows.isNotEmpty && rows.first['v'] == secret;

      final pass = !headerIsPlaintext && !containsSecret && wrongKeyRejected && rightKeyWorked;
      setState(() {
        _storageTestResult = pass
            ? 'PASS — file header not plaintext, secret not found in raw bytes, wrong key rejected, right key read the real value back'
            : 'FAIL — headerIsPlaintext=$headerIsPlaintext containsSecret=$containsSecret '
                'wrongKeyRejected=$wrongKeyRejected rightKeyWorked=$rightKeyWorked';
      });
    } catch (e) {
      setState(() => _storageTestResult = 'FAIL — $e');
    } finally {
      await dir.delete(recursive: true);
      if (mounted) setState(() => _isTestingStorage = false);
    }
  }

  /// Task 6 — the fourth on-screen milestone: a real PIN gates access to
  /// this person's own data, on this device, for real. If [userId] has no
  /// partition yet, sets one up (PIN-wraps their already-enrolled token,
  /// see [LocalUnlockService]'s class doc for why the PIN wraps the token
  /// rather than being mixed into the database key itself). If a partition
  /// already exists, attempts to unlock it with the entered PIN -- shown on
  /// screen as PASS (with the recovered token, proving it's the real one,
  /// not just "a decrypt didn't throw") or a clear wrong-PIN rejection.
  Future<void> _setUpOrUnlockPin(String userId) async {
    final pin = _pinController.text;
    if (pin.isEmpty) {
      setState(() => _unlockError = 'Enter a PIN first.');
      return;
    }
    setState(() {
      _isUnlocking = true;
      _unlockError = null;
      _unlockResult = null;
    });
    try {
      final alreadySetUp = await _localUnlockService.isSetUp(userId);
      if (!alreadySetUp) {
        final token = await _enrollmentService.storedToken(userId);
        if (token == null) {
          setState(() => _unlockError = 'No enrolled token found for this user yet — enroll first.');
          return;
        }
        await _localUnlockService.setUpPin(userId: userId, pin: pin, enrollmentToken: token);
        setState(() {
          _unlockResult = 'PIN set up for this profile on this device.';
          _pinIsSetUp = Future.value(true);
        });
      } else {
        final unwrapped = await _localUnlockService.unlock(userId: userId, pin: pin);
        setState(() {
          _unlockResult = unwrapped == null
              ? null
              : 'PASS — unlocked with the correct PIN, recovered token: '
                  '${unwrapped.substring(0, unwrapped.length.clamp(0, 24))}…';
          _unlockError = unwrapped == null ? 'Wrong PIN — rejected.' : null;
        });
      }
    } catch (e) {
      setState(() => _unlockError = 'Local unlock failed: $e');
    } finally {
      if (mounted) setState(() => _isUnlocking = false);
    }
  }

  /// [UserIdentityService.signChallenge] resolves the DER-vs-P1363 question
  /// this used to be blocked on -- confirmed against real Android hardware
  /// 2026-09-10, see docs/roster-vault/Troubleshooting/Known Issues.md and
  /// the story checkpoint's Task 5 entry.
  ChallengeSigner _productionChallengeSigner(String userId) {
    return (nonce) => _userIdentityService.signChallenge(userId, nonce);
  }

  Widget _buildOfflineSignInSection(DeviceIdentity identity) {
    if (widget.signedInUser == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('Offline Sign-In', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'Verifies the stored token locally -- signature, expiry, device-id, epoch, and a '
          'challenge-response -- with no network call.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('offlineSignInButton'),
            onPressed: _isSigningInOffline ? null : () => _signInOffline(identity),
            child: _isSigningInOffline
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign in offline (verify stored token)'),
          ),
        ),
        if (_offlineSignInError != null) ...[
          const SizedBox(height: 12),
          Text(_offlineSignInError!, key: const Key('offlineSignInError'), style: const TextStyle(color: Colors.orange)),
        ],
        if (_offlineSignInResult != null) ...[
          const SizedBox(height: 16),
          Text(
            _offlineSignInResult!.isValid
                ? 'Result: PASS'
                : 'Result: FAIL (${_offlineSignInResult!.failure!.name})',
            key: const Key('offlineSignInStatus'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _offlineSignInResult!.isValid ? Colors.green : Colors.red,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStorageTestSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('Encrypted Storage (Task 6)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'Proves real encryption is active on this device -- writes through '
          'EncryptedPartitionStore, checks the raw file bytes, confirms a wrong key is rejected.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('storageTestButton'),
            onPressed: _isTestingStorage ? null : _testEncryptedStorage,
            child: _isTestingStorage
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Test encrypted storage'),
          ),
        ),
        if (_storageTestResult != null) ...[
          const SizedBox(height: 16),
          Text(
            _storageTestResult!,
            key: const Key('storageTestResult'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _storageTestResult!.startsWith('PASS') ? Colors.green : Colors.red,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLocalUnlockSection() {
    final user = widget.signedInUser;
    if (user == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('Local Unlock (Task 6)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'A real PIN gates this profile\'s data on this device. First use sets it up '
          '(PIN-wraps the already-enrolled token); after that, the same button attempts to unlock.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        FutureBuilder<bool>(
          future: _pinIsSetUp,
          builder: (context, snapshot) {
            final isSetUp = snapshot.data ?? false;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('pinField'),
                  controller: _pinController,
                  decoration: InputDecoration(labelText: isSetUp ? 'Enter PIN to unlock' : 'Choose a PIN'),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  enabled: !_isUnlocking,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('pinSubmitButton'),
                    onPressed: _isUnlocking ? null : () => _setUpOrUnlockPin(user.userId),
                    child: _isUnlocking
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(isSetUp ? 'Unlock' : 'Set PIN'),
                  ),
                ),
              ],
            );
          },
        ),
        if (_unlockError != null) ...[
          const SizedBox(height: 12),
          Text(_unlockError!, key: const Key('pinError'), style: const TextStyle(color: Colors.red)),
        ],
        if (_unlockResult != null) ...[
          const SizedBox(height: 12),
          Text(
            _unlockResult!,
            key: const Key('pinResult'),
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ],
      ],
    );
  }

  Widget _buildEnrollmentSection(DeviceIdentity identity) {
    if (widget.signedInUser == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('Enrollment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('enrollButton'),
            onPressed: _isEnrolling ? null : () => _enroll(identity),
            child: _isEnrolling
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enroll this device'),
          ),
        ),
        if (_enrollError != null) ...[
          const SizedBox(height: 12),
          Text(_enrollError!, style: const TextStyle(color: Colors.red)),
        ],
        if (_enrollmentResult != null && _verifiedClaims != null) ...[
          const SizedBox(height: 16),
          Text(
            _verifiedClaims!.signatureValid ? 'Signature: VALID' : 'Signature: INVALID',
            key: const Key('enrollmentSignatureStatus'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _verifiedClaims!.signatureValid ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          const Text('Decoded claims:'),
          SelectableText(
            const JsonEncoder.withIndent('  ').convert(_verifiedClaims!.claims),
            key: const Key('enrollmentClaimsText'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roster Vault — Device Debug'),
        actions: [
          if (widget.onSignedOut != null)
            TextButton(
              key: const Key('signOutButton'),
              onPressed: widget.onSignedOut,
              child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<DeviceIdentity>(
          future: _deviceIdentity,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                'Device identity failed: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              );
            }
            final identity = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.signedInUser != null) ...[
                  Text(
                    'Signed in as: ${widget.signedInUser!.username}',
                    key: const Key('signedInUserText'),
                    style: const TextStyle(fontSize: 16, color: Colors.green),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Device identity', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (identity == null)
                  const Text('Generating device keypair…')
                else ...[
                  SelectableText('Device ID: ${identity.deviceId}'),
                  const SizedBox(height: 8),
                  const Text('Device public key:'),
                  SelectableText(identity.publicKeyPem, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  _buildEnrollmentSection(identity),
                  _buildOfflineSignInSection(identity),
                  _buildStorageTestSection(),
                  _buildLocalUnlockSection(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
