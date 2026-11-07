import 'package:flutter/material.dart';
import 'privacy_api.dart';

const _bg = Color(0xFF08060B);
const _panel = Color(0xFF151019);
const _pink = Color(0xFFFF4FA3);
const _rose = Color(0xFFFFB4D4);
const _text = Color(0xFFF7F1F7);
const _muted = Color(0xFFAA9EAE);
const _success = Color(0xFF39E875);

/// Privacy/account UI intended to be opened from Profile > Privacy.
/// Requires a deployed API; it deliberately has no client-side OTP fallback.
class PrivacyAccountScreen extends StatefulWidget {
  const PrivacyAccountScreen({super.key, required this.api, required this.english});
  final PrivacyApi api;
  final bool english;

  @override
  State<PrivacyAccountScreen> createState() => _PrivacyAccountScreenState();
}

class _PrivacyAccountScreenState extends State<PrivacyAccountScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _account;
  late final AnimationController _successAnimation = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  bool _busy = false;

  String t(String ru, String en) => widget.english ? en : ru;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _successAnimation.dispose(); super.dispose(); }

  Future<void> _load() async {
    try { final result = await widget.api.getAccount(); if (mounted) setState(() => _account = Map<String, dynamic>.from(result['account'] as Map)); }
    on PrivacyApiException catch (e) { _message(_errorText(e.code)); }
    catch (_) { _message(t('Не удалось связаться с сервером.', 'Could not reach the server.')); }
  }

  String _errorText(String code) => switch (code) {
    'verified_email_required' => t('Сначала привяжите и подтвердите Gmail.', 'Link and verify a Gmail address first.'),
    'email_unavailable' => t('Этот адрес уже используется.', 'That email is already in use.'),
    'username_unavailable' => t('Этот логин уже занят.', 'That username is already taken.'),
    'invalid_or_expired_code' => t('Код неверный или срок его действия истёк.', 'The code is invalid or expired.'),
    'weak_password' => t('Пароль: минимум 10 символов, строчные и заглавные буквы и цифра.', 'Use 10+ characters with lowercase, uppercase, and a digit.'),
    'rate_limited' => t('Слишком много попыток. Попробуйте позже.', 'Too many attempts. Try again later.'),
    'invalid_credentials' => t('Неверный пароль.', 'Incorrect password.'),
    'verification_required' => t('Сначала подтвердите код из письма.', 'Verify the email code first.'),
    _ => t('Операция не выполнена. Попробуйте позже.', 'The operation failed. Try again later.'),
  };

  void _message(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }

  Future<void> _dialog(String title, Future<void> Function(StateSetter refresh, BuildContext dialogContext) content) async {
    await showDialog<void>(context: context, barrierDismissible: !_busy, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, refresh) => AlertDialog(
        backgroundColor: _panel,
        title: Text(title, style: const TextStyle(color: _text)),
        content: SingleChildScrollView(child: _DialogForm(content: content, refresh: refresh, dialogContext: dialogContext)),
      ),
    ));
  }

  Future<void> _changeUsername() async {
    final controller = TextEditingController(); final code = TextEditingController();
    String? challenge; String? grant; bool sent = false;
    await _dialog(t('Сменить логин', 'Change username'), (refresh, dialogContext) async {
      if (grant == null) {
        return _formStep(dialogContext, refresh, children: [
          Text(t('Текущий логин: ${_account?['username'] ?? '—'}', 'Current username: ${_account?['username'] ?? '—'}'), style: const TextStyle(color: _muted)),
          TextField(controller: controller, style: const TextStyle(color: _text), decoration: InputDecoration(labelText: t('Новый логин', 'New username'))),
          if (sent) TextField(controller: code, style: const TextStyle(color: _text), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Код из письма', 'Email code'))),
          Row(children: [TextButton(onPressed: _busy ? null : () async { final value=controller.text.trim(); if (!RegExp(r'^[A-Za-z0-9._-]{3,32}$').hasMatch(value)) { _message(t('3–32 символа: латиница, цифры, точка, дефис или подчёркивание.', 'Use 3–32 letters, digits, dot, dash or underscore.')); return; } await _run(refresh, () async { challenge=await widget.api.sendCode(purpose:'username_change'); sent=true; }); }, child: Text(t('Отправить код', 'Send code'), style: const TextStyle(color:_rose))),
            TextButton(onPressed: _busy || !sent ? null : () async { await _run(refresh, () async { final result=await widget.api.verifyCode(challengeId:challenge!,code:code.text.trim()); grant=result['grant'] as String; }); }, child: Text(t('Подтвердить', 'Verify'), style: const TextStyle(color:_pink)))]),
          if (grant != null) FilledButton(onPressed: _busy ? null : () async { await _run(refresh, () async { final result=await widget.api.changeUsername(controller.text.trim(),grant!); _account=Map<String,dynamic>.from(result['account'] as Map); if (dialogContext.mounted) Navigator.pop(dialogContext); _showSuccess(t('Ваш логин успешно изменён!','Your username was changed!')); }); }, child: Text(t('Сохранить','Save'))),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t('Закрыть','Close'))),
        ]);
      }
    });
    controller.dispose(); code.dispose();
  }

  Future<void> _changePassword() async {
    final code = TextEditingController(), password = TextEditingController(), confirm = TextEditingController();
    String? challenge; String? grant; bool sent = false;
    await _dialog(t('Сменить пароль','Change password'), (refresh, dialogContext) async => _formStep(dialogContext, refresh, children: [
      if (grant == null) ...[
        Text('${t('Код будет отправлен на','A code will be sent to')} ${_account?['email'] ?? '—'}', style: const TextStyle(color:_muted)),
        if (sent) TextField(controller: code, keyboardType: TextInputType.number, style: const TextStyle(color:_text), decoration: InputDecoration(labelText:t('Код из письма','Email code'))),
        Wrap(children:[TextButton(onPressed:_busy?null:() async { await _run(refresh,() async { challenge=await widget.api.sendCode(purpose:'password_change'); sent=true; }); },child:Text(t('Отправить / повторить код','Send / resend code'),style:const TextStyle(color:_rose))),
          TextButton(onPressed:_busy||!sent?null:() async { await _run(refresh,() async { final result=await widget.api.verifyCode(challengeId:challenge!,code:code.text.trim()); grant=result['grant'] as String; }); },child:Text(t('Подтвердить','Verify'),style:const TextStyle(color:_pink)))])
      ] else ...[
        TextField(controller:password,obscureText:true,style:const TextStyle(color:_text),decoration:InputDecoration(labelText:t('Новый пароль','New password'))),
        TextField(controller:confirm,obscureText:true,style:const TextStyle(color:_text),decoration:InputDecoration(labelText:t('Повторите пароль','Repeat password'))),
        FilledButton(onPressed:_busy?null:() async { if(password.text!=confirm.text){_message(t('Пароли не совпадают.','Passwords do not match.'));return;} if(password.text.length<10||!RegExp(r'[a-z]').hasMatch(password.text)||!RegExp(r'[A-Z]').hasMatch(password.text)||!RegExp(r'\d').hasMatch(password.text)){_message(t('Нужно 10+ символов, строчные и заглавные буквы и цифра.','Use 10+ characters with lowercase, uppercase, and a digit.'));return;} await _run(refresh,() async { await widget.api.changePassword(password.text,grant!); if(dialogContext.mounted)Navigator.pop(dialogContext); _showSuccess(t('Ваш пароль успешно изменён!','Your password was changed!')); }); },child:Text(t('Сохранить пароль','Save password'))),
      ],
      TextButton(onPressed:()=>Navigator.pop(dialogContext),child:Text(t('Закрыть','Close'))),
    ]));
    code.dispose(); password.dispose(); confirm.dispose();
  }

  Future<void> _changeEmail({bool replace = false}) async {
    final email=TextEditingController(); final code=TextEditingController();
    String? challenge; String? grant; bool sent=false;
    await _dialog(replace?t('Изменить Gmail','Change Gmail'):t('Привязать Gmail','Link Gmail'),(refresh,dialogContext) async => _formStep(dialogContext,refresh,children:[
      if(replace) Text('${t('Текущий адрес:','Current address:')} ${_account?['email']??'—'}',style:const TextStyle(color:_muted)),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,style:const TextStyle(color:_text),decoration:InputDecoration(labelText:t('Адрес Gmail','Gmail address'))),
      if(sent)TextField(controller:code,keyboardType:TextInputType.number,style:const TextStyle(color:_text),decoration:InputDecoration(labelText:t('Код из письма','Email code'))),
      Wrap(children:[TextButton(onPressed:_busy?null:() async { final value=email.text.trim(); if(!RegExp(r'^[A-Z0-9._%+-]+@gmail\.com$',caseSensitive:false).hasMatch(value)){_message(t('Введите корректный адрес @gmail.com.','Enter a valid @gmail.com address.'));return;} await _run(refresh,() async { challenge=await widget.api.sendCode(purpose:replace?'email_change':'email_link',email:value);sent=true; }); },child:Text(t('Отправить / повторить код','Send / resend code'),style:const TextStyle(color:_rose))),
      TextButton(onPressed:_busy||!sent?null:() async { await _run(refresh,() async { final result=await widget.api.verifyCode(challengeId:challenge!,code:code.text.trim());grant=result['grant'] as String; }); },child:Text(t('Подтвердить','Verify'),style:const TextStyle(color:_pink)))]),
      if(grant!=null)FilledButton(onPressed:_busy?null:() async { await _run(refresh,() async { final result=await widget.api.changeEmail(email.text.trim(),grant!);_account=Map<String,dynamic>.from(result['account'] as Map);if(dialogContext.mounted)Navigator.pop(dialogContext);_showSuccess(t(replace?'Ваша почта успешно изменена!':'Ваша почта успешно привязана!',replace?'Your email was changed!':'Your email was linked!')); }); },child:Text(t('Сохранить Gmail','Save Gmail'))),
      TextButton(onPressed:()=>Navigator.pop(dialogContext),child:Text(t('Закрыть','Close'))),
    ]));
    email.dispose();code.dispose();
  }

  Future<void> _unlinkEmail() async {
    if (_account?['email'] == null) return;
    final password=TextEditingController(); final code=TextEditingController(); String? challenge; String? grant; bool sent=false;
    await _dialog(t('Отвязать Gmail','Unlink Gmail'),(refresh,dialogContext) async => _formStep(dialogContext,refresh,children:[
      Text('${t('Код отправим на','We will send a code to')} ${_account?['email']}',style:const TextStyle(color:_muted)),
      TextField(controller:password,obscureText:true,style:const TextStyle(color:_text),decoration:InputDecoration(labelText:t('Текущий пароль','Current password'))),
      if(sent)TextField(controller:code,keyboardType:TextInputType.number,style:const TextStyle(color:_text),decoration:InputDecoration(labelText:t('Код из письма','Email code'))),
      Wrap(children:[TextButton(onPressed:_busy?null:() async { await _run(refresh,() async { challenge=await widget.api.sendCode(purpose:'email_unlink');sent=true; }); },child:Text(t('Отправить код','Send code'),style:const TextStyle(color:_rose))),
      TextButton(onPressed:_busy||!sent?null:() async { await _run(refresh,() async { final result=await widget.api.verifyCode(challengeId:challenge!,code:code.text.trim());grant=result['grant'] as String; }); },child:Text(t('Подтвердить код','Verify code'),style:const TextStyle(color:_pink)))]),
      if(grant!=null)FilledButton(onPressed:_busy?null:() async { await _run(refresh,() async { await widget.api.unlinkEmail(password:password.text,grant:grant!);_account?['email']=null;_account?['email_verified_at']=null;if(dialogContext.mounted)Navigator.pop(dialogContext);_showSuccess(t('Gmail отвязан','Gmail unlinked')); }); },child:Text(t('Подтвердить отвязку','Confirm unlink'))),
      TextButton(onPressed:()=>Navigator.pop(dialogContext),child:Text(t('Отмена','Cancel'))),
    ]));
    password.dispose();code.dispose();
  }

  Future<void> _run(StateSetter refresh, Future<void> Function() action) async {
    refresh(() => _busy = true);
    try { await action(); }
    on PrivacyApiException catch(e) { _message(_errorText(e.code)); }
    catch(_) { _message(t('Не удалось связаться с сервером.','Could not reach the server.')); }
    finally { if(mounted)refresh(() => _busy=false); }
  }

  Future<void> _formStep(BuildContext dialogContext, StateSetter refresh, {required List<Widget> children}) async {
    for(final child in children) if(child is TextButton || child is FilledButton) {
      // Children own their async handlers; this method exists to keep dialog form content isolated.
    }
  }

  void _showSuccess(String text) { _successAnimation.forward(from:0); _message(text); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor:_bg,
    appBar:AppBar(backgroundColor:_bg,foregroundColor:_rose,title:Text(t('Конфиденциальность','Privacy'))),
    body:_account==null?const Center(child:CircularProgressIndicator(color:_pink)):ListView(padding:const EdgeInsets.all(18),children:[
      _tile(Icons.person_outline,t('Сменить логин','Change username'),_account?['username']?.toString()??'',_changeUsername),
      _tile(Icons.lock_outline,t('Сменить пароль','Change password'),t('Подтверждение по Gmail','Verify by email'),_changePassword),
      if(_account?['email']==null)_tile(Icons.email_outlined,t('Привязать Gmail','Link Gmail'),t('Не привязан','Not linked'),()=>_changeEmail())
      else ...[_tile(Icons.email_outlined,_account!['email'].toString(),t('Подтверждён','Verified'),()=>_changeEmail(replace:true)),_tile(Icons.edit_outlined,t('Изменить Gmail','Change Gmail'),'',()=>_changeEmail(replace:true)),_tile(Icons.link_off,t('Отвязать Gmail','Unlink Gmail'),'',_unlinkEmail)],
      const SizedBox(height:24),
      ScaleTransition(scale:CurvedAnimation(parent:_successAnimation,curve:Curves.elasticOut),child:FadeTransition(opacity:_successAnimation,child:const Icon(Icons.check_circle,color:_success,size:56))),
    ]),
  );

  Widget _tile(IconData icon,String title,String subtitle,VoidCallback onTap)=>Card(color:_panel,child:ListTile(leading:Icon(icon,color:_rose),title:Text(title,style:const TextStyle(color:_text)),subtitle:subtitle.isEmpty?null:Text(subtitle,style:const TextStyle(color:_muted)),trailing:const Icon(Icons.chevron_right,color:_muted),onTap:onTap));
}

class _DialogForm extends StatelessWidget {
  const _DialogForm({required this.content,required this.refresh,required this.dialogContext});
  final Future<void> Function(StateSetter,BuildContext) content;
  final StateSetter refresh;
  final BuildContext dialogContext;
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(future:content(refresh,dialogContext),builder:(context,snapshot)=>const SizedBox.shrink());
}
