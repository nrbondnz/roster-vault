import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/device_identity_service.dart';
import '../services/enrollment_service.dart';
import '../services/issuer_public_key.dart';
import '../services/local_unlock_service.dart';
import '../services/offline_verifier.dart';
import '../services/roster_registry_service.dart';
import '../services/user_identity_service.dart';

/// Task 7 — "the actual 'pick your name' surface the requirement
/// describes" (story checkpoint). This is the app's real home screen now
/// (see [RosterVaultApp.build] in main.dart) — [AuthGate]/[LoginScreen]/
/// [DeviceDebugScreen] are the "Add a person" sub-flow reached from here,
/// not the forced entry point they were through Task 6.
///
/// Reads the on-device [RosterRegistryService] list -- entirely local, no
/// network call, works with the device's radios off. "Add a person" is the
/// one online-only surface (per
/// docs/roster-vault/Architecture/Multi-User Partitioning.md, "Roster
/// Management Is an Online-Only Surface") -- greyed out, honestly, when
/// [Connectivity] reports no network, rather than left enabled to fail
/// confusingly partway through a Cognito sign-in.
class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  final _rosterRegistryService = RosterRegistryService();
  final _localUnlockService = LocalUnlockService();
  late Future<List<RosterEntry>> _rosterFuture;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _rosterFuture = _rosterRegistryService.listProfiles();
    _checkConnectivity();
    Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) setState(() => _isOnline = _hasRealConnection(results));
    });
  }

  bool _hasRealConnection(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    if (mounted) setState(() => _isOnline = _hasRealConnection(result));
  }

  void _refreshRoster() {
    // Deliberately a block body, not `=> _rosterFuture = ...` -- an arrow
    // body's value is the assignment expression's value (the Future
    // itself), which Flutter's setState explicitly rejects at runtime
    // ("setState() callback argument returned a Future"). Caught live on
    // the real device: the write succeeded but the roster silently never
    // refreshed, because this exact bug threw before the rebuild completed.
    setState(() {
      _rosterFuture = _rosterRegistryService.listProfiles();
    });
  }

  Future<void> _addPerson() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthGate()));
    _refreshRoster();
  }

  Future<void> _selectProfile(RosterEntry entry) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => _PinPromptDialog(displayName: entry.displayName),
    );
    if (pin == null || pin.isEmpty) return;
    if (!mounted) return;
    try {
      final token = await _localUnlockService.unlock(userId: entry.userId, pin: pin);
      if (token == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wrong PIN — rejected.')));
        }
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileHomeScreen(entry: entry, recoveredToken: token)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unlock failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roster Vault')),
      body: FutureBuilder<List<RosterEntry>>(
        future: _rosterFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final roster = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: roster.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No one is enrolled on this device yet.',
                            key: Key('rosterEmptyMessage'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: roster.length,
                        itemBuilder: (context, i) {
                          final entry = roster[i];
                          return ListTile(
                            key: Key('rosterEntry_${entry.userId}'),
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(entry.displayName),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _selectProfile(entry),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('addPersonButton'),
                      onPressed: _isOnline ? _addPerson : null,
                      icon: const Icon(Icons.person_add),
                      label: Text(_isOnline ? 'Add a person' : 'Add a person (offline)'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PinPromptDialog extends StatefulWidget {
  const _PinPromptDialog({required this.displayName});
  final String displayName;

  @override
  State<_PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<_PinPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('PIN for ${widget.displayName}'),
      content: TextField(
        key: const Key('rosterPinField'),
        controller: _controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'PIN'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('rosterPinSubmit'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

/// Task 7 — where a selected profile actually lands: runs the real
/// [OfflineVerifier] against the token [LocalUnlockService.unlock] just
/// recovered (the same check Task 5 proved correct and Task 6 proved is
/// reachable only with the right PIN), then shows the result. "Sign Out"
/// here is deliberately just a [Navigator.pop] -- Task 7's own Verify bar
/// ("fast switch... no round trip") is satisfied by there being nothing
/// else to do: nothing async, no network call, no re-derivation, because
/// this profile's data was never left "open" anywhere beyond this screen's
/// own local variables.
class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({super.key, required this.entry, required this.recoveredToken});

  final RosterEntry entry;
  final String recoveredToken;

  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  final _deviceIdentityService = DeviceIdentityService();
  final _userIdentityService = UserIdentityService();
  final _enrollmentService = EnrollmentService();
  final _offlineVerifier = const OfflineVerifier();
  late final Future<OfflineVerificationResult> _verifyFuture;

  @override
  void initState() {
    super.initState();
    _verifyFuture = _verify();
  }

  Future<OfflineVerificationResult> _verify() async {
    final identity = await _deviceIdentityService.ensureDeviceIdentity();
    final knownEpoch = await _enrollmentService.knownEpoch(widget.entry.userId) ?? 0;
    final userPubKey = await _userIdentityService.ensureUserKeyPair(widget.entry.userId);
    return _offlineVerifier.verify(
      token: widget.recoveredToken,
      issuerPublicKeyPem: issuerPublicKeyPem,
      expectedDeviceId: identity.deviceId,
      currentKnownEpoch: knownEpoch,
      userPublicKeyPem: userPubKey,
      signChallenge: (nonce) => _userIdentityService.signChallenge(widget.entry.userId, nonce),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.displayName),
        actions: [
          TextButton(
            key: const Key('rosterSignOutButton'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder<OfflineVerificationResult>(
          future: _verifyFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Sign-in check failed: ${snapshot.error}', style: const TextStyle(color: Colors.red));
            }
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final result = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome, ${widget.entry.displayName}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text(
                  result.isValid ? 'Offline sign-in: PASS' : 'Offline sign-in: FAIL (${result.failure!.name})',
                  key: const Key('profileSignInStatus'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: result.isValid ? Colors.green : Colors.red,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
