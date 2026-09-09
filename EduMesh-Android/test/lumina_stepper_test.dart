import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edumesh_android/l10n/app_localizations.dart';
import 'package:edumesh_android/shared/widgets/lumina_stepper.dart';

/// Regression test: step labels once used a spacing constant
/// (`AppSpacing.xs.sp` = 4px) as their font size, rendering the
/// Welcome/Login/Access labels unreadably small on phones.
void main() {
  Future<void> pumpStepper(WidgetTester tester) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(360, 780),
        minTextAdapt: true,
        builder: (_, __) => const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: LuminaStepper(currentStep: 0)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('step labels use a legible size, not a spacing constant',
      (tester) async {
    await pumpStepper(tester);

    for (final label in ['Welcome', 'Login/Register', 'Access']) {
      final text = tester.widget<Text>(find.text(label));
      // null = inherits the theme's labelSmall (~11px). Anything explicit
      // must stay at caption size or above, never near 4px.
      final size = text.style?.fontSize;
      expect(size == null || size >= 10, isTrue,
          reason: '$label label font size was $size');
    }
  });
}
