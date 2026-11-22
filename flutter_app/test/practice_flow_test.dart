import 'package:bill_saathi/core/coach_service.dart';
import 'package:bill_saathi/core/reference_validator.dart';
import 'package:bill_saathi/core/sample_bill.dart';
import 'package:bill_saathi/ui/bill_saathi_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reference validation', () {
    const validator = ReferenceValidator();

    test(
      'accepts the synthetic reference in Arabic and Eastern Arabic digits',
      () {
        expect(validator.validate(SampleBill.reference).isValid, isTrue);
        expect(validator.validate('۰۰۰۰۱۲۳۴۰۰۴۳۰۲').isValid, isTrue);
        expect(validator.validate('٠٠٠٠١٢٣٤٠٠٤٣٠٢').isValid, isTrue);
      },
    );

    test('identifies the meter number and malformed references', () {
      expect(
        validator.validate(SampleBill.meter).issue,
        ReferenceIssue.meterNumber,
      );
      expect(validator.validate('').issue, ReferenceIssue.empty);
      expect(validator.validate('123').issue, ReferenceIssue.wrongLength);
      expect(
        validator.validate('99991234004302').issue,
        ReferenceIssue.notSampleReference,
      );
    });
  });

  test('cloud prompt cannot contain entered values or fixture identifiers', () {
    const coach = CoachService();
    for (final topic in HelpTopic.values) {
      for (final language in AppLanguage.values) {
        final prompt = coach.publicPrompt(topic, language);
        expect(prompt, isNot(contains(SampleBill.reference)));
        expect(prompt, isNot(contains(SampleBill.meter)));
        expect(prompt, isNot(contains('4,280')));
        expect(prompt, contains('Topic:'));
      }
    }
  });

  test('unsafe cloud output falls back to the built-in guide', () async {
    final coach = CoachService(
      cloudTextGenerator: (_) async => 'Use account 12345678901234.',
    );
    final reply = await coach.explain(
      HelpTopic.findReference,
      AppLanguage.english,
    );
    expect(reply.source, HelpSource.reviewedGuide);
  });

  test(
    'on-device explanation is English only and rejects invented identifiers',
    () async {
      var calls = 0;
      final coach = CoachService(
        localTextGenerator: (_) async {
          calls++;
          return 'Use the number 12345678901234.';
        },
      );
      final english = await coach.explainOnDevice(
        HelpTopic.findReference,
        AppLanguage.english,
      );
      final urdu = await coach.explainOnDevice(
        HelpTopic.findReference,
        AppLanguage.urdu,
      );
      expect(english.source, HelpSource.reviewedGuide);
      expect(urdu.source, HelpSource.reviewedGuide);
      expect(calls, 1);
    },
  );

  testWidgets('payer can correct a meter number and finish practice', (
    tester,
  ) async {
    await tester.pumpWidget(const BillSaathiApp(coach: CoachService()));
    await tester.tap(find.text('Start practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this sample bill'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), SampleBill.meter);
    await tester.ensureVisible(find.text('Review details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('That is the meter number'), findsOneWidget);

    await tester.ensureVisible(find.text('Show me on the bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show me on the bill'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Source: built-in guide'), findsOneWidget);
    await tester.ensureVisible(find.text('Return to reference'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return to reference'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), SampleBill.reference);
    await tester.ensureVisible(find.text('Review details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review details'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm practice payment'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirm practice payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm practice payment'));
    await tester.pumpAndSettle();
    expect(find.text('No payment was sent'), findsOneWidget);
  });
}
