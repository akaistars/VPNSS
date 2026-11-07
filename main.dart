import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

const _background = Color(0xFF05050A);
const _surface = Color(0xFF100D18);
const _text = Color(0xFFF2ECFA);
const _muted = Color(0xFF9A8EAD);
const _accent = Color(0xFFE9E9F0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setMinimumSize(const Size(440, 700));
    await windowManager.setSize(const Size(440, 820));
    await windowManager.setAlignment(Alignment.center);
  }

  runApp(const SpiderVpnApp());
}

class SpiderVpnApp extends StatefulWidget {
  const SpiderVpnApp({super.key});

  @override
  State<SpiderVpnApp> createState() => _SpiderVpnAppState();
}

class _SpiderVpnAppState extends State<SpiderVpnApp> {
  String? _username;
  String? _password;
  bool _loggedIn = false;
  String? _gmail;
  String? _phone;

  void _register(String username, String password) {
    setState(() {
      _username = username;
      _password = password;
    });
  }

  bool _login(String username, String password) {
    if (username.trim().toLowerCase() !=
            (_username ?? '').trim().toLowerCase() ||
        password != _password) {
      return false;
    }

    setState(() => _loggedIn = true);
    return true;
  }

  bool _changePassword(String oldPassword, String newPassword) {
    if (_password == null || oldPassword != _password) {
      return false;
    }

    setState(() => _password = newPassword);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spider VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: !_loggedIn
          ? _AuthScreen(
              hasAccount: _username != null,
              onRegister: _register,
              onLogin: _login,
            )
          : _ProfileScreen(
              username: _username ?? '',
              gmail: _gmail,
              phone: _phone,
              onGmailChanged: (value) => setState(() => _gmail = value),
              onPhoneChanged: (value) => setState(() => _phone = value),
              onChangePassword: _changePassword,
              onLogout: () => setState(() => _loggedIn = false),
            ),
    );
  }
}

class _AuthScreen extends StatefulWidget {
  const _AuthScreen({
    required this.hasAccount,
    required this.onRegister,
    required this.onLogin,
  });

  final bool hasAccount;
  final void Function(String username, String password) onRegister;
  final bool Function(String username, String password) onLogin;

  @override
  State<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<_AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (widget.hasAccount) {
      if (!widget.onLogin(username, password)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный логин или пароль.')),
        );
      }
      return;
    }

    widget.onRegister(username, password);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Демо-аккаунт создан. Теперь войдите с этими данными.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = widget.hasAccount;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '🕷️',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 64),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'SPIDER VPN',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _text,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      isLogin ? 'Вход в аккаунт' : 'Создать аккаунт',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(labelText: 'Логин'),
                      validator: (value) {
                        if ((value ?? '').trim().length < 3) {
                          return 'Введите не менее 3 символов';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Пароль'),
                      validator: (value) {
                        if ((value ?? '').length < 6) {
                          return 'Пароль должен содержать минимум 6 символов';
                        }
                        return null;
                      },
                    ),
                    if (!isLogin) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _repeatController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Повторите пароль',
                        ),
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return 'Пароли не совпадают';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(isLogin ? 'Войти' : 'Зарегистрироваться'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Демо-вход: аккаунт и пароль хранятся только до закрытия приложения.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen({
    required this.username,
    required this.gmail,
    required this.phone,
    required this.onGmailChanged,
    required this.onPhoneChanged,
    required this.onChangePassword,
    required this.onLogout,
  });

  final String username;
  final String? gmail;
  final String? phone;
  final ValueChanged<String> onGmailChanged;
  final ValueChanged<String> onPhoneChanged;
  final bool Function(String oldPassword, String newPassword) onChangePassword;
  final VoidCallback onLogout;

  Future<void> _showPrivacy(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            20,
            18,
            18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Конфиденциальность',
                style: TextStyle(
                  color: _text,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Логин, пароль, Gmail и номер телефона',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline, color: _accent),
                title: const Text('Логин'),
                subtitle: Text(username),
              ),
              _PrivacyAction(
                icon: Icons.email_outlined,
                title: 'Привязать Gmail',
                subtitle: gmail ?? 'Не привязан',
                onTap: () async {
                  final value = await _askForValue(
                    context,
                    title: 'Привязать Gmail',
                    label: 'Адрес Gmail',
                    initialValue: gmail ?? '',
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (!RegExp(
                        r'^[A-Z0-9._%+-]+@gmail\.com$',
                        caseSensitive: false,
                      ).hasMatch(value)) {
                        return 'Введите адрес вида name@gmail.com';
                      }
                      return null;
                    },
                  );
                  if (value != null) onGmailChanged(value);
                },
              ),
              _PrivacyAction(
                icon: Icons.phone_outlined,
                title: 'Привязать номер телефона',
                subtitle: phone ?? 'Не привязан',
                onTap: () async {
                  final value = await _askForValue(
                    context,
                    title: 'Привязать номер телефона',
                    label: 'Номер телефона',
                    initialValue: phone ?? '',
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (!RegExp(r'^\+?[0-9 ()-]{7,20}$').hasMatch(value)) {
                        return 'Введите корректный номер телефона';
                      }
                      return null;
                    },
                  );
                  if (value != null) onPhoneChanged(value);
                },
              ),
              _PrivacyAction(
                icon: Icons.lock_outline,
                title: 'Сменить пароль',
                onTap: () async {
                  final changed = await _changePassword(context);
                  if (changed && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Пароль успешно изменён.'),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _askForValue(
    BuildContext context, {
    required String title,
    required String label,
    required String initialValue,
    required TextInputType keyboardType,
    required String? Function(String value) validator,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _surface,
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
            validator: (value) => validator((value ?? '').trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  Future<bool> _changePassword(BuildContext context) async {
    final oldPasswordController = TextEditingController();
    final oldPasswordKey = GlobalKey<FormState>();

    final oldPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Введите старый пароль'),
        content: Form(
          key: oldPasswordKey,
          child: TextFormField(
            controller: oldPasswordController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Старый пароль'),
            validator: (value) {
              if ((value ?? '').isEmpty) return 'Введите старый пароль';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (oldPasswordKey.currentState!.validate()) {
                Navigator.pop(dialogContext, oldPasswordController.text);
              }
            },
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );

    oldPasswordController.dispose();
    if (oldPassword == null || !context.mounted) return false;

    final newPasswordController = TextEditingController();
    final repeatPasswordController = TextEditingController();
    final newPasswordKey = GlobalKey<FormState>();

    final newPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Введите новый пароль'),
        content: Form(
          key: newPasswordKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: newPasswordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Новый пароль'),
                validator: (value) {
                  if ((value ?? '').length < 6) {
                    return 'Минимум 6 символов';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: repeatPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Повторите новый пароль',
                ),
                validator: (value) {
                  if (value != newPasswordController.text) {
                    return 'Пароли не совпадают';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (newPasswordKey.currentState!.validate()) {
                Navigator.pop(dialogContext, newPasswordController.text);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    newPasswordController.dispose();
    repeatPasswordController.dispose();

    if (newPassword == null || !context.mounted) return false;

    final changed = onChangePassword(oldPassword, newPassword);

    if (!changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Старый пароль введён неверно.')),
      );
    }

    return changed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Выйти',
                    onPressed: onLogout,
                    icon: const Icon(Icons.close, color: _accent),
                  ),
                  const Expanded(
                    child: Text(
                      '🕷️  Spider VPN',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _text,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text(
                    'Профиль',
                    style: TextStyle(
                      color: _text,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'УПРАВЛЕНИЕ АККАУНТОМ',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ProfileTile(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Конфиденциальность',
                    subtitle: 'Логин, пароль, Gmail и номер телефона',
                    onTap: () => _showPrivacy(context),
                  ),
                  const SizedBox(height: 10),
                  _ProfileTile(
                    icon: Icons.lock_outline,
                    title: 'Сменить пароль',
                    subtitle: 'Сначала потребуется старый пароль',
                    onTap: () async {
                      final changed = await _changePassword(context);
                      if (changed && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Пароль успешно изменён.'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyAction extends StatelessWidget {
  const _PrivacyAction({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: _accent),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right, color: _muted),
      onTap: onTap,
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        leading: Icon(icon, color: _accent),
        title: Text(
          title,
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: _muted),
        ),
        trailing: const Icon(Icons.chevron_right, color: _muted),
        onTap: onTap,
      ),
    );
  }
}
