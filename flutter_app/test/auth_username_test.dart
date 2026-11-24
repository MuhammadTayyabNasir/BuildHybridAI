import 'package:flutter_test/flutter_test.dart';
import 'package:pma/services/auth_service.dart';

void main() {
  test('accepts a short username', () {
    expect(AuthService.normalizeUsername('admin'), 'admin');
  });

  test('accepts the full email the console account was created with', () {
    expect(AuthService.normalizeUsername('admin@pma.app'), 'admin');
    expect(AuthService.normalizeUsername('Operator1@PMA.app'), 'operator1');
  });

  test('ignores spaces a phone keyboard inserts', () {
    expect(AuthService.normalizeUsername(' admin@ pma.app '), 'admin');
  });
}
