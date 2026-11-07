import 'dart:async';

/// Stable boundary between the privacy UI and account storage/verification.
/// Replace [DemoPrivacyRepository] with a server-backed implementation later;
/// the screen should not need redesign when the backend is introduced.
abstract interface class PrivacyRepository {
  String get username;
  String? get email;

  Future<String> sendVerificationCode({required String purpose, required String target});
  Future<void> confirmVerificationCode({required String challengeId, required String code});
  Future<void> changeUsername({required String username, required String challengeId});
  Future<void> changePassword({required String password, required String challengeId});
  Future<void> changeEmail({required String email, required String challengeId});
  Future<void> unlinkEmail({required String currentPassword, required String challengeId});
}

/// In-process DEMO implementation. The fixed code is intentionally visible
/// and explicitly labelled DEMO in the UI. No messages are sent, no secrets
/// leave the device, and this class must never be treated as authentication.
class DemoPrivacyRepository implements PrivacyRepository {
  DemoPrivacyRepository({String username = 'spider_user', String? email, String demoPassword = 'DemoPass123!'})
      : _username = username,
        _email = email,
        _demoPassword = demoPassword;

  static const demoCode = '123456';
  String _username;
  String? _email;
  String _demoPassword;
  final Map<String, _Challenge> _challenges = {};

  @override
  String get username => _username;
  @override
  String? get email => _email;

  @override
  Future<String> sendVerificationCode({required String purpose, required String target}) async {
    if (purpose != 'link_email' && purpose != 'change_email' && purpose != 'change_username' && purpose != 'change_password' && purpose != 'unlink_email') {
      throw const PrivacyDemoException('unsupported_action');
    }
    if ((purpose == 'change_password' || purpose == 'change_username' || purpose == 'unlink_email') && (_email == null || _email!.isEmpty)) {
      throw const PrivacyDemoException('email_required');
    }
    if (purpose == 'link_email' && _email != null) throw const PrivacyDemoException('email_already_linked');
    final normalizedTarget = target.trim().toLowerCase();
    if ((purpose == 'link_email' || purpose == 'change_email') && !DemoPrivacyRepository.isValidGmail(normalizedTarget)) {
      throw const PrivacyDemoException('invalid_email');
    }
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    _challenges[id] = _Challenge(purpose, normalizedTarget, DateTime.now().add(const Duration(minutes: 10)));
    return id;
  }

  @override
  Future<void> confirmVerificationCode({required String challengeId, required String code}) async {
    final challenge = _challenges[challengeId];
    if (challenge == null || challenge.consumed || challenge.verified || DateTime.now().isAfter(challenge.expiresAt) || challenge.attempts >= 5) {
      throw const PrivacyDemoException('invalid_or_expired_code');
    }
    if (code != demoCode) {
      challenge.attempts++;
      throw const PrivacyDemoException('invalid_or_expired_code');
    }
    challenge.verified = true;
  }

  _Challenge _verified(String id, String purpose) {
    final challenge = _challenges[id];
    if (challenge == null || !challenge.verified || challenge.consumed || challenge.purpose != purpose || DateTime.now().isAfter(challenge.expiresAt)) {
      throw const PrivacyDemoException('verification_required');
    }
    challenge.consumed = true;
    return challenge;
  }

  @override
  Future<void> changeUsername({required String username, required String challengeId}) async {
    final value = username.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]{3,32}$').hasMatch(value)) throw const PrivacyDemoException('invalid_username');
    _verified(challengeId, 'change_username');
    _username = value;
  }

  @override
  Future<void> changePassword({required String password, required String challengeId}) async {
    if (!isStrongPassword(password)) throw const PrivacyDemoException('weak_password');
    _verified(challengeId, 'change_password');
    _demoPassword = password;
  }

  @override
  Future<void> changeEmail({required String email, required String challengeId}) async {
    final challenge = _challenges[challengeId];
    if (challenge == null || !challenge.verified || challenge.consumed || DateTime.now().isAfter(challenge.expiresAt)) {
      throw const PrivacyDemoException('verification_required');
    }
    final purpose = challenge.purpose;
    if (purpose != 'link_email' && purpose != 'change_email') throw const PrivacyDemoException('verification_required');
    final value = email.trim().toLowerCase();
    if (value != challenge.target || !isValidGmail(value)) throw const PrivacyDemoException('verification_required');
    if (purpose == 'link_email' && _email != null) throw const PrivacyDemoException('email_already_linked');
    challenge.consumed = true;
    _email = value;
  }

  @override
  Future<void> unlinkEmail({required String currentPassword, required String challengeId}) async {
    if (currentPassword != _demoPassword) throw const PrivacyDemoException('invalid_password');
    _verified(challengeId, 'unlink_email');
    _email = null;
  }

  static bool isValidGmail(String value) => RegExp(r'^[A-Z0-9._%+-]+@gmail\.com$', caseSensitive: false).hasMatch(value);
  static bool isStrongPassword(String value) => value.length >= 10 && value.length <= 128 && RegExp(r'[a-z]').hasMatch(value) && RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'\d').hasMatch(value);
}

class _Challenge {
  _Challenge(this.purpose, this.target, this.expiresAt);
  final String purpose;
  final String target;
  final DateTime expiresAt;
  int attempts = 0;
  bool verified = false;
  bool consumed = false;
}

class PrivacyDemoException implements Exception {
  const PrivacyDemoException(this.code);
  final String code;
  @override
  String toString() => code;
}
