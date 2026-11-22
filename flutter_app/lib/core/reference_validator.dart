import 'sample_bill.dart';

enum ReferenceIssue { empty, meterNumber, wrongLength, notSampleReference }

class ReferenceResult {
  const ReferenceResult(this.digits, this.issue);

  final String digits;
  final ReferenceIssue? issue;

  bool get isValid => issue == null;
}

/// Validation is deterministic; the assistant cannot override this result.
class ReferenceValidator {
  const ReferenceValidator();

  static const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  static const _easternArabicIndic = '۰۱۲۳۴۵۶۷۸۹';

  String normalize(String input) {
    final result = StringBuffer();
    for (final rune in input.runes) {
      final character = String.fromCharCode(rune);
      final ascii = character.codeUnitAt(0) - 48;
      if (ascii >= 0 && ascii <= 9) {
        result.write(character);
        continue;
      }
      final arabic = _arabicIndic.indexOf(character);
      if (arabic >= 0) {
        result.write(arabic);
        continue;
      }
      final eastern = _easternArabicIndic.indexOf(character);
      if (eastern >= 0) result.write(eastern);
    }
    return result.toString();
  }

  ReferenceResult validate(String input) {
    final digits = normalize(input);
    if (digits.isEmpty) return const ReferenceResult('', ReferenceIssue.empty);
    if (digits == normalize(SampleBill.meter)) {
      return ReferenceResult(digits, ReferenceIssue.meterNumber);
    }
    if (digits.length != SampleBill.reference.length) {
      return ReferenceResult(digits, ReferenceIssue.wrongLength);
    }
    if (digits != SampleBill.reference) {
      return ReferenceResult(digits, ReferenceIssue.notSampleReference);
    }
    return ReferenceResult(digits, null);
  }
}
