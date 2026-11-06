import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/auth/auth_repository.dart';

void main() {
  test('email validation', () {
    expect(AuthValidation.email(''), isNotNull);
    expect(AuthValidation.email('nope'), isNotNull);
    expect(AuthValidation.email('a@b'), isNotNull);
    expect(AuthValidation.email(' sam@example.com '), isNull);
  });
  test('new password rules', () {
    expect(AuthValidation.newPassword('Short1'), isNotNull);
    expect(AuthValidation.newPassword('alllowercase123'), isNotNull);
    expect(AuthValidation.newPassword('NoDigitsHereAtAll'), isNotNull);
    expect(AuthValidation.newPassword('Correct7Horse'), isNull);
  });
}
