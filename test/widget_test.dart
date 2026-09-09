import 'package:flutter_test/flutter_test.dart';

import 'package:roster_vault/main.dart';

void main() {
  testWidgets('App launches and shows the device debug screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RosterVaultApp());

    expect(find.text('Roster Vault — Device Debug'), findsOneWidget);
    expect(find.text('Device identity'), findsOneWidget);

    // DeviceDebugScreen.initState races real device-keygen against a
    // 15-second timeout (main.dart) so it never spins forever on real
    // hardware. In a widget test there's no real platform channel behind
    // biometric_signature, so that race never resolves on its own --
    // without fast-forwarding past it, its Timer is still pending when the
    // test ends and the framework's own invariant check fails the test
    // (independently of the assertions above, which already passed by this
    // point). testWidgets already runs inside a fake-async zone, so pumping
    // past the timeout duration fires it without a real 15s wall-clock wait.
    await tester.pump(const Duration(seconds: 16));
  });
}
