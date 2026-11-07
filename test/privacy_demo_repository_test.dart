import 'package:flutter_test/flutter_test.dart';
import 'package:spider_vpn/privacy/privacy_repository.dart';

void main() {
  test('DEMO verification gates account changes and code is single-use', () async {
    final repository = DemoPrivacyRepository();
    final id = await repository.sendVerificationCode(purpose: 'change_username', target: '');
    expect(repository.username, 'spider_user');
    await expectLater(repository.confirmVerificationCode(challengeId: id, code: '000000'), throwsA(isA<PrivacyDemoException>()));
    await repository.confirmVerificationCode(challengeId: id, code: DemoPrivacyRepository.demoCode);
    await repository.changeUsername(username: 'renamed_user', challengeId: id);
    expect(repository.username, 'renamed_user');
    await expectLater(repository.confirmVerificationCode(challengeId: id, code: DemoPrivacyRepository.demoCode), throwsA(isA<PrivacyDemoException>()));
  });

  test('Gmail binding/change/unlink require verified DEMO code', () async {
    final repository = DemoPrivacyRepository();
    final first = await repository.sendVerificationCode(purpose: 'link_email', target: 'one@gmail.com');
    await repository.confirmVerificationCode(challengeId: first, code: DemoPrivacyRepository.demoCode);
    await repository.changeEmail(email: 'one@gmail.com', challengeId: first);
    expect(repository.email, 'one@gmail.com');

    final replace = await repository.sendVerificationCode(purpose: 'change_email', target: 'two@gmail.com');
    await repository.confirmVerificationCode(challengeId: replace, code: DemoPrivacyRepository.demoCode);
    await repository.changeEmail(email: 'two@gmail.com', challengeId: replace);
    expect(repository.email, 'two@gmail.com');

    final unlink = await repository.sendVerificationCode(purpose: 'unlink_email', target: 'two@gmail.com');
    await repository.confirmVerificationCode(challengeId: unlink, code: DemoPrivacyRepository.demoCode);
    await repository.unlinkEmail(currentPassword: 'DemoPass123!', challengeId: unlink);
    expect(repository.email, isNull);
  });

  test('DEMO password change verifies code, confirmation policy, and updates password', () async {
    final repository = DemoPrivacyRepository(email: 'user@gmail.com');
    final id = await repository.sendVerificationCode(purpose: 'change_password', target: 'user@gmail.com');
    await repository.confirmVerificationCode(challengeId: id, code: DemoPrivacyRepository.demoCode);
    await repository.changePassword(password: 'UpdatedPass456!', challengeId: id);
    expect(repository.username, 'spider_user');
  });
}
