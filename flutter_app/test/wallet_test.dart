import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:bill_saathi/ui/wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  testWidgets('confirmed transfer debits account and creates a receipt', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Wallet(practice: (_) => const SizedBox())),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'send money');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Send to Ayesha'));
    await tester.tap(find.text('Send to Ayesha'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '125.50');
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Rs 125.50'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Rs 49874.50'), findsOneWidget);
  });
  for (final example in {
    'I want to donate, please open it for me': 'Donations',
    'Help me pay my driving challans for Punjab government':
        'Punjab traffic challans',
    'میں چندہ دینا چاہتا ہوں': 'Donations',
    'پنجاب کا چالان کھولیں': 'Punjab traffic challans',
    'میرا بیلنس دکھائیں': 'My account',
    'رقم بھیجیں': 'Send money',
    'میرا کارڈ': 'My card',
    'میری آخری ادائیگی دکھائیں': 'Payment history',
    'meri akhri payment dikhao': 'Payment history',
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
