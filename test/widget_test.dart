import 'package:flutter_test/flutter_test.dart';

import 'package:roster_vault/main.dart';

void main() {
  testWidgets('App launches and shows the device debug screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RosterVaultApp());

    expect(find.text('Roster Vault — Device Debug'), findsOneWidget);
    expect(find.text('Device identity'), findsOneWidget);
  });
}
