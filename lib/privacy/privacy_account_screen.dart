import 'package:flutter/material.dart';
import 'privacy_api.dart';

const _bg = Color(0xFF08060B);
const _panel = Color(0xFF151019);
const _pink = Color(0xFFFF4FA3);
const _rose = Color(0xFFFFB4D4);
const _text = Color(0xFFF7F1F7);
const _muted = Color(0xFFAA9EAE);
const _success = Color(0xFF39E875);

/// Privacy and account settings surface. OTP codes and permissions are always
/// validated by the configured account API, never simulated in this widget.
class PrivacyAccountScreen extends StatefulWidget {
  const PrivacyAccountScreen({super.key, required this.api, required this.english});
  final PrivacyApi api;
  final bool english;

  @override
  State<PrivacyAccountScreen> createState() => _PrivacyAccountScreenState();
}

class _PrivacyAccountScreenState extends State<PrivacyAccountScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _account;
  bool _loading = true;
  bool _busy = false;
  late final AnimationController _success = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  String t(String ru, String en) => widget.english ? en : ru;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _success.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final account = await widget.api.getAccount();
      if (mounted) setState(() { _account = account; _loading = false; });
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _showError(error);
    }
  }

  String _errorText(String code) => switch (code) {
    'not_authenticated' || 'unauthorized' || 'session_expired' => t('Войдите через серверный аккаунт, чтобы управлять данными.', 'Sign in with a server account to manage your data.'),
    'verified_email_required' => t('Сначала привяжите и подтвердите Gmail.', 'Link and verify a Gmail address first.'),
    'email_unavailable' => t('Этот адрес уже используется.', 'That email is already in use.'),
    'username_unavailable' => t('Этот логин уже занят.', 'That username is already taken.'),
    'invalid_or_expired_code' => t('Код неверный, использован или срок его действия истёк.', 'The code is invalid, used, or expired.'),
    'weak_password' => t('Нужно не менее 10 символов, строчные и заглавные буквы и цифра.', 'Use at least 10 characters with lowercase, uppercase, and a digit.'),
    'rate_limited' => t('Слишком много попыток. Попробуйте позже.', 'Too many attempts. Try again later.'),
    'invalid_credentials' => t('Неверный пароль.', 'Incorrect password.'),
    'verification_required' => t('Сначала подтвердите код из письма.', 'Verify the email code first.'),
    'invalid_username' => t('Логин должен содержать 3–32 латинских символа, цифры, точку, дефис или подчёркивание.', 'Username must be 3–32 characters: letters, digits, dot, dash or underscore.'),
    _ => t('Операция не выполнена. Проверьте подключение к API и попробуйте снова.', 'The operation failed. Check the API connection and try again.'),
  };

  void _showError(Object error) {
    final code = error is PrivacyApiException ? error.code : 'network_error';
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(code))));
  }

  Future<void> _perform(Future<void> Function() action, StateSetter refresh) async {
    refresh(() => _busy = true);
    try { await action(); }
    catch (error) { _showError(error); }
    finally { if (mounted) refresh(() => _busy = false); }
  }

  Future<void> _showFlow(String title, Widget Function(StateSetter, BuildContext) content) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !_busy,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          backgroundColor: _panel,
          title: Text(title, style: const TextStyle(color: _text)),
          content: SingleChildScrollView(child: content(refresh, dialogContext)),
        ),
      ),
    );
  }

  Future<void> _requestGrant({required String purpose, required String? email, required TextEditingController code, required StateSetter refresh, required void Function(String) onGrant, required void Function(String) onChallenge, required void Function(bool) onSent}) async {
    await _perform(() async {
      final challenge = await widget.api.sendCode(purpose: purpose, email: email);
      onChallenge(challenge);
      onSent(true);
      _message(t('Код отправлен. Он действует 10 минут.', 'Code sent. It expires in 10 minutes.'));
    }, refresh);
  }

  Future<void> _verify({required String challenge, required TextEditingController code, required StateSetter refresh, required void Function(String) onGrant}) async {
    await _perform(() async {
      final result = await widget.api.verifyCode(challengeId: challenge, code: code.text.trim());
      onGrant(result['grant'] as String);
    }, refresh);
  }

  Future<void> _changeUsername() async {
    final username = TextEditingController(); final code = TextEditingController();
    String? challenge, grant; bool sent = false;
    await _showFlow(t('Сменить логин', 'Change username'), (refresh, dialog) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${t('Текущий логин:', 'Current username:')} ${_account?['username'] ?? '—'}', style: const TextStyle(color: _muted)),
      const SizedBox(height: 12),
      TextField(controller: username, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Новый логин', 'New username'))),
      if (grant == null) ...[
        if (sent) TextField(controller: code, keyboardType: TextInputType.number, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Код из Gmail', 'Email code'))),
        Wrap(alignment: WrapAlignment.end, children: [
          TextButton(onPressed: _busy ? null : () { final value = username.text.trim(); if (!RegExp(r'^[A-Za-z0-9._-]{3,32}$').hasMatch(value)) { _message(_errorText('invalid_username')); return; } _requestGrant(purpose: 'username_change', email: null, code: code, refresh: refresh, onGrant: (v) => grant = v, onChallenge: (v) => challenge = v, onSent: (v) => sent = v); }, child: Text(t('Отправить / повторить код', 'Send / resend code'), style: const TextStyle(color: _rose))),
          TextButton(onPressed: _busy || !sent ? null : () => _verify(challenge: challenge!, code: code, refresh: refresh, onGrant: (v) => grant = v), child: Text(t('Подтвердить', 'Verify'), style: const TextStyle(color: _pink))),
        ]),
      ],
      if (grant != null) FilledButton(onPressed: _busy ? null : () => _perform(() async { final result = await widget.api.changeUsername(username.text.trim(), grant!); setState(() => _account = Map<String, dynamic>.from(result['account'] as Map)); if (dialog.mounted) Navigator.pop(dialog); _showSuccess(t('Ваш логин успешно изменён!', 'Your username was changed!')); }, refresh), child: Text(t('Сохранить', 'Save')),
      TextButton(onPressed: _busy ? null : () => Navigator.pop(dialog), child: Text(t('Отмена', 'Cancel'))),
    ]));
    username.dispose(); code.dispose();
  }

  Future<void> _changePassword() async {
    final code = TextEditingController(), password = TextEditingController(), confirm = TextEditingController();
    String? challenge, grant; bool sent = false;
    await _showFlow(t('Сменить пароль', 'Change password'), (refresh, dialog) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (grant == null) ...[
        Text('${t('Код будет отправлен на', 'A code will be sent to')} ${_account?['email'] ?? '—'}', style: const TextStyle(color: _muted)),
        if (sent) TextField(controller: code, keyboardType: TextInputType.number, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Код из письма', 'Email code'))),
        Wrap(alignment: WrapAlignment.end, children: [
          TextButton(onPressed: _busy ? null : () => _requestGrant(purpose: 'password_change', email: null, code: code, refresh: refresh, onGrant: (v) => grant = v, onChallenge: (v) => challenge = v, onSent: (v) => sent = v), child: Text(t('Отправить / повторить код', 'Send / resend code'), style: const TextStyle(color: _rose))),
          TextButton(onPressed: _busy || !sent ? null : () => _verify(challenge: challenge!, code: code, refresh: refresh, onGrant: (v) => grant = v), child: Text(t('Подтвердить', 'Verify'), style: const TextStyle(color: _pink))),
        ]),
      ] else ...[
        TextField(controller: password, obscureText: true, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Новый пароль', 'New password'))),
        TextField(controller: confirm, obscureText: true, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Повторите пароль', 'Repeat password'))),
        const SizedBox(height: 8),
        Text(t('Минимум 10 символов: строчные и заглавные буквы, цифра.', 'At least 10 characters, including lowercase, uppercase, and a digit.'), style: const TextStyle(color: _muted, fontSize: 12)),
        FilledButton(onPressed: _busy ? null : () {
          if (password.text != confirm.text) { _message(t('Пароли не совпадают.', 'Passwords do not match.')); return; }
          if (password.text.length < 10 || !RegExp(r'[a-z]').hasMatch(password.text) || !RegExp(r'[A-Z]').hasMatch(password.text) || !RegExp(r'\d').hasMatch(password.text)) { _message(_errorText('weak_password')); return; }
          _perform(() async { await widget.api.changePassword(password.text, grant!); if (dialog.mounted) Navigator.pop(dialog); _showSuccess(t('Ваш пароль успешно изменён!', 'Your password was changed!')); }, refresh);
        }, child: Text(t('Сохранить пароль', 'Save password'))),
      ],
      TextButton(onPressed: _busy ? null : () => Navigator.pop(dialog), child: Text(t('Закрыть', 'Close'))),
    ]));
    code.dispose(); password.dispose(); confirm.dispose();
  }

  Future<void> _changeEmail({required bool replacing}) async {
    final email = TextEditingController(text: replacing ? _account?['email']?.toString() ?? '' : '');
    final code = TextEditingController(); String? challenge, grant; bool sent = false;
    await _showFlow(replacing ? t('Изменить Gmail', 'Change Gmail') : t('Привязать Gmail', 'Link Gmail'), (refresh, dialog) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (replacing) Text('${t('Текущий адрес:', 'Current address:')} ${_account?['email'] ?? '—'}', style: const TextStyle(color: _muted)),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Адрес Gmail', 'Gmail address'))),
      if (grant == null) ...[
        if (sent) TextField(controller: code, keyboardType: TextInputType.number, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Код из письма', 'Email code'))),
        Wrap(alignment: WrapAlignment.end, children: [
          TextButton(onPressed: _busy ? null : () { final value = email.text.trim(); if (!RegExp(r'^[A-Z0-9._%+-]+@gmail\.com$', caseSensitive: false).hasMatch(value)) { _message(t('Введите корректный адрес @gmail.com.', 'Enter a valid @gmail.com address.')); return; } _requestGrant(purpose: replacing ? 'email_change' : 'email_link', email: value, code: code, refresh: refresh, onGrant: (v) => grant = v, onChallenge: (v) => challenge = v, onSent: (v) => sent = v); }, child: Text(t('Отправить / повторить код', 'Send / resend code'), style: const TextStyle(color: _rose))),
          TextButton(onPressed: _busy || !sent ? null : () => _verify(challenge: challenge!, code: code, refresh: refresh, onGrant: (v) => grant = v), child: Text(t('Подтвердить', 'Verify'), style: const TextStyle(color: _pink))),
        ]),
      ],
      if (grant != null) FilledButton(onPressed: _busy ? null : () => _perform(() async { final result = await widget.api.changeEmail(email.text.trim(), grant!); setState(() => _account = Map<String, dynamic>.from(result['account'] as Map)); if (dialog.mounted) Navigator.pop(dialog); _showSuccess(t(replacing ? 'Ваша почта успешно изменена!' : 'Ваша почта успешно привязана!', replacing ? 'Your email was changed!' : 'Your email was linked!')); }, refresh), child: Text(t('Сохранить Gmail', 'Save Gmail')),
      TextButton(onPressed: _busy ? null : () => Navigator.pop(dialog), child: Text(t('Отмена', 'Cancel'))),
    ]));
    email.dispose(); code.dispose();
  }

  Future<void> _unlinkEmail() async {
    final password = TextEditingController(), code = TextEditingController(); String? challenge, grant; bool sent = false;
    await _showFlow(t('Отвязать Gmail', 'Unlink Gmail'), (refresh, dialog) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${t('Код будет отправлен на', 'A code will be sent to')} ${_account?['email'] ?? '—'}', style: const TextStyle(color: _muted)),
      TextField(controller: password, obscureText: true, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Текущий пароль', 'Current password'))),
      if (sent) TextField(controller: code, keyboardType: TextInputType.number, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Код из письма', 'Email code'))),
      Wrap(alignment: WrapAlignment.end, children: [
        TextButton(onPressed: _busy ? null : () => _requestGrant(purpose: 'email_unlink', email: null, code: code, refresh: refresh, onGrant: (v) => grant = v, onChallenge: (v) => challenge = v, onSent: (v) => sent = v), child: Text(t('Отправить / повторить код', 'Send / resend code'), style: const TextStyle(color: _rose))),
        TextButton(onPressed: _busy || !sent ? null : () => _verify(challenge: challenge!, code: code, refresh: refresh, onGrant: (v) => grant = v), child: Text(t('Подтвердить код', 'Verify code'), style: const TextStyle(color: _pink))),
      ]),
      if (grant != null) FilledButton(onPressed: _busy ? null : () => _perform(() async { await widget.api.unlinkEmail(password: password.text, grant: grant!); setState(() { _account?['email'] = null; _account?['email_verified_at'] = null; }); if (dialog.mounted) Navigator.pop(dialog); _showSuccess(t('Gmail отвязан.', 'Gmail unlinked.')); }, refresh), child: Text(t('Подтвердить отвязку', 'Confirm unlink')),
      TextButton(onPressed: _busy ? null : () => Navigator.pop(dialog), child: Text(t('Отмена', 'Cancel'))),
    ]));
    password.dispose(); code.dispose();
  }

  void _message(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }

  Future<void> _showSuccess(String text) async {
    _success.forward(from: 0);
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      backgroundColor: _panel,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ScaleTransition(scale: CurvedAnimation(parent: _success, curve: Curves.elasticOut), child: FadeTransition(opacity: _success, child: const Icon(Icons.check_circle, color: _success, size: 62))),
        const SizedBox(height: 16), Text(text, textAlign: TextAlign.center, style: const TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w600)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Готово', 'Done')))],
    ));
  }

  Future<void> _openPrivacyOptions() async {
    await showModalBottomSheet<void>(context: context, backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.person_outline, color: _rose), title: Text(t('Сменить логин', 'Change username'), style: const TextStyle(color: _text)), onTap: () { Navigator.pop(context); _changeUsername(); }),
        ListTile(leading: const Icon(Icons.lock_outline, color: _rose), title: Text(t('Сменить пароль', 'Change password'), style: const TextStyle(color: _text)), onTap: () { Navigator.pop(context); _changePassword(); }),
        ListTile(leading: const Icon(Icons.email_outlined, color: _rose), title: Text(_account?['email'] == null ? t('Привязать Gmail', 'Link Gmail') : _account!['email'].toString(), style: const TextStyle(color: _text)), onTap: () { Navigator.pop(context); _changeEmail(replacing: _account?['email'] != null); }),
        if (_account?['email'] != null) ...[
          ListTile(leading: const Icon(Icons.edit_outlined, color: _rose), title: Text(t('Изменить Gmail', 'Change Gmail'), style: const TextStyle(color: _text)), onTap: () { Navigator.pop(context); _changeEmail(replacing: true); }),
          ListTile(leading: const Icon(Icons.link_off, color: _rose), title: Text(t('Отвязать Gmail', 'Unlink Gmail'), style: const TextStyle(color: _text)), onTap: () { Navigator.pop(context); _unlinkEmail(); }),
        ],
      ])));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(backgroundColor: _bg, foregroundColor: _rose, title: Text(t('Конфиденциальность', 'Privacy'))),
    body: _loading ? const Center(child: CircularProgressIndicator(color: _pink)) : _account == null
      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, color: _rose, size: 44), const SizedBox(height: 12),
          Text(t('Нет подключения к серверу аккаунтов. Настройте API и войдите в серверный аккаунт.', 'Account server is not connected. Configure the API and sign in to a server account.'), textAlign: TextAlign.center, style: const TextStyle(color: _text)),
          const SizedBox(height: 12), OutlinedButton(onPressed: _load, child: Text(t('Повторить', 'Retry'))),
        ])))
      : ListView(padding: const EdgeInsets.all(18), children: [
        Text('${t('Аккаунт', 'Account')}: ${_account?['username'] ?? ''}', style: const TextStyle(color: _muted)),
        const SizedBox(height: 12),
        _tile(Icons.privacy_tip_outlined, t('Настройки аккаунта', 'Account settings'), t('Логин, пароль и Gmail', 'Username, password and Gmail'), _openPrivacyOptions),
        const SizedBox(height: 12),
        _tile(Icons.person_outline, t('Сменить логин', 'Change username'), _account?['username']?.toString() ?? '', _changeUsername),
        _tile(Icons.lock_outline, t('Сменить пароль', 'Change password'), t('Подтверждение по Gmail', 'Email verification'), _changePassword),
        _tile(Icons.email_outlined, _account?['email']?.toString() ?? t('Привязать Gmail', 'Link Gmail'), _account?['email_verified_at'] == null ? t('Не привязан', 'Not linked') : t('Подтверждён', 'Verified'), () => _changeEmail(replacing: _account?['email'] != null)),
        if (_account?['email'] != null) ...[
          _tile(Icons.edit_outlined, t('Изменить Gmail', 'Change Gmail'), '', () => _changeEmail(replacing: true)),
          _tile(Icons.link_off, t('Отвязать Gmail', 'Unlink Gmail'), '', _unlinkEmail),
        ],
      ]),
  );

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    color: _panel,
    child: ListTile(leading: Icon(icon, color: _rose), title: Text(title, style: const TextStyle(color: _text)),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, style: const TextStyle(color: _muted)),
      trailing: const Icon(Icons.chevron_right, color: _muted), onTap: onTap),
  );
}
