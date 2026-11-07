import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spider_vpn/privacy/privacy_account_screen.dart';
import 'package:spider_vpn/privacy/privacy_repository.dart';

void main() {
  testWidgets('privacy demo explains no emails are sent and exposes account actions', (tester) async {
    final repository = DemoPrivacyRepository();
    await tester.pumpWidget(MaterialApp(home: PrivacyAccountScreen(repository: repository, english: false)));
    expect(find.textContaining('DEMO-режим'), findsOneWidget);
    expect(find.textContaining('123456'), findsOneWidget);
    expect(find.text('Сменить логин'), findsOneWidget);
    expect(find.text('Сменить пароль'), findsOneWidget);
    expect(find.text('Привязать Gmail'), findsOneWidget);
  });
}
