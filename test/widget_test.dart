import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:roster_vault/main.dart';
import 'package:roster_vault/screens/login_screen.dart';
import 'package:roster_vault/services/device_identity_service.dart';

void main() {
  // DeviceDebugScreen and LoginScreen are tested directly (not via
  // RosterVaultApp's real entry point, _AuthGate) because _AuthGate calls
  // Amplify.configure(), which needs real platform-channel-backed plugins
  // that don't exist in a plain widget test -- see Task 4b's note in the
  // story checkpoint. This mirrors the same reasoning Task 3 already
  // applied to DeviceIdentityService's own real-plugin call.
  testWidgets('DeviceDebugScreen shows the device debug UI', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DeviceDebugScreen(deviceIdentityService: DeviceIdentityService())),
    );

    expect(find.text('Roster Vault — Device Debug'), findsOneWidget);
    expect(find.text('Device identity'), findsOneWidget);

    // See the comment on the equivalent pump in the pre-Task-4b version of
    // this test: DeviceDebugScreen.initState races real device-keygen
    // against a 15-second timeout, whose Timer must be advanced past
    // before the test ends or the framework's own invariant check fails
    // the test independently of the assertions above.
    await tester.pump(const Duration(seconds: 16));
  });

  testWidgets('LoginScreen shows email, password, and sign-in controls', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen(onSignedIn: (_) {})));

    expect(find.text('Roster Vault — Sign In'), findsOneWidget);
    expect(find.byKey(const Key('loginEmailField')), findsOneWidget);
    expect(find.byKey(const Key('loginPasswordField')), findsOneWidget);
    expect(find.byKey(const Key('loginSubmitButton')), findsOneWidget);
  });
}
