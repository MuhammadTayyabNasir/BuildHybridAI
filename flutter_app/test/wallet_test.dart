import 'package:bill_saathi/ui/wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final example in {
    'I want to donate, please open it for me': 'Donations',
    'Help me pay my driving challans for Punjab government':
        'Punjab traffic challans',
    'Give me details of my last payments': 'Payment history',
  }.entries) {
    testWidgets(example.key, (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Wallet(practice: (_) => const SizedBox())),
      );
      await tester.enterText(find.byType(TextField), example.key);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(example.value),
        ),
        findsOneWidget,
      );
    });
  }
}
