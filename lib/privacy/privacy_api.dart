import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PrivacyApiException implements Exception {
  const PrivacyApiException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// HTTP adapter for the server-side account API. It never generates or accepts
/// verification codes locally; OTP issuance and verification are server-only.
class PrivacyApi {
  PrivacyApi({required this.baseUri, HttpClient? client, FlutterSecureStorage? storage})
      : _client = client ?? HttpClient(),
        _storage = storage ?? const FlutterSecureStorage();

  final Uri baseUri;
  final HttpClient _client;
  final FlutterSecureStorage _storage;
  static const _tokenKey = 'spider_account_session';

  Future<void> saveSessionToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<void> clearSessionToken() => _storage.delete(key: _tokenKey);

  Future<Map<String, dynamic>> getAccount() => _request('GET', '/v1/account');

  Future<String> sendCode({required String purpose, String? email}) async {
    final result = await _request('POST', '/v1/verification/send', body: {
      'purpose': purpose,
      if (email != null) 'email': email,
    });
    return result['challengeId'] as String;
  }

  Future<Map<String, dynamic>> verifyCode({required String challengeId, required String code}) =>
      _request('POST', '/v1/verification/confirm', body: {'challengeId': challengeId, 'code': code});

  Future<Map<String, dynamic>> changeUsername(String username, String grant) =>
      _request('PATCH', '/v1/account/username', body: {'username': username, 'grant': grant});

  Future<void> changePassword(String password, String grant) async {
    await _request('PATCH', '/v1/account/password', body: {'password': password, 'grant': grant});
  }

  Future<Map<String, dynamic>> changeEmail(String email, String grant) =>
      _request('PATCH', '/v1/account/email', body: {'email': email, 'grant': grant});

  Future<void> unlinkEmail({required String password, required String grant}) async {
    await _request('DELETE', '/v1/account/email', body: {'password': password, 'grant': grant});
  }

  Future<Map<String, dynamic>> _request(String method, String path, {Map<String, dynamic>? body}) async {
    final token = await _storage.read(key: _tokenKey);
    final request = await _client.openUrl(method, baseUri.resolve(path));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PrivacyApiException(decoded['error'] as String? ?? 'request_failed');
    }
    return decoded;
  }
}
