import 'package:flutter_test/flutter_test.dart';
import 'package:spider_vpn/privacy/privacy_api.dart';

void main() {
  test('API exception preserves server error code without exposing payloads', () {
    const error = PrivacyApiException('invalid_or_expired_code');
    expect(error.toString(), 'invalid_or_expired_code');
  });
}
