import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PrivacyApiException implements Exception {
  const PrivacyApiException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// HTTP client for the account service. The API owns OTP generation and
/// validation; this client never creates, stores, or logs a verification code.
class PrivacyApi {
  PrivacyApi({required this.baseUri, HttpClient? client, FlutterSecureStorage? storage})
      : _client = client ?? HttpClient(),
        _storage = storage ?? const FlutterSecureStorage();

  /// Configure with `--dart-define=SPIDER_API_URL=https://api.example.com/`.
  final Uri baseUri;
  final HttpClient _client;
  final FlutterSecureStorage _storage;
  static const _tokenKey = 'spider_account_session';

  Future<void> saveSessionToken(String token) => _storage.write(key: _tokenKey, value: token);
  Future<void> clearSessionToken() => _storage.delete(key: _tokenKey);

  Future<Map<String, dynamic>> register({required String username, required String password}) async {
    final response = await _request('POST', '/v1/auth/register', body: {'username': username, 'password': password}, authenticated: false);
    await saveSessionToken(response['token'] as String);
    return Map<String, dynamic>.from(response['account'] as Map);
  }

  Future<Map<String, dynamic>> login({required String username, required String password}) async {
    final response = await _request('POST', '/v1/auth/login', body: {'username': username, 'password': password}, authenticated: false);
    await saveSessionToken(response['token'] as String);
    return Map<String, dynamic>.from(response['account'] as Map);
  }

  Future<Map<String, dynamic>> getAccount() async =>
      Map<String, dynamic>.from((await _request('GET', '/v1/account'))['account'] as Map);

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

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? body, bool authenticated = true}) async {
    final request = await _client.openUrl(method, baseUri.resolve(path));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (authenticated) {
      final token = await _storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) throw const PrivacyApiException('not_authenticated');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
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
