import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:edumesh_android/features/auth/presentation/welcome_page.dart';
import 'package:edumesh_android/main.dart';

void main() {
  testWidgets('Logged-out app boots to the welcome page with its entry CTA',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: LuminaApp(isLoggedIn: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Enter Portal'),
        findsOneWidget);
  });
}
