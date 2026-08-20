import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edumesh_android/features/auth/presentation/login_page.dart';
import 'package:edumesh_android/features/auth/presentation/profile_picker_page.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

/// Widget tests for the [ProfilePickerPage]: it must list every locally known
/// profile, badge the active one, offer the add-profile action, and open the
/// [LoginPage] when that action is tapped.
void main() {
  const usersKey = 'lumina_users_list_secure';

  Widget wrap() {
    return const ScreenUtilInit(
      designSize: Size(360, 800),
      minTextAdapt: true,
      splitScreenMode: true,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfilePickerPage(),
      ),
    );
  }

  testWidgets('picker lists known profiles and badges the active one', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      usersKey:
          '[{"username":"priya","userId":"u1","displayName":"Priya"},'
              '{"username":"arjun","userId":"u2","displayName":"Arjun"}]',
      'lumina_unique_user_id': 'u2',
    });

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Arjun'), findsOneWidget);
    expect(find.text('@priya'), findsOneWidget);
    expect(find.text('@arjun'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
  });

  testWidgets('empty picker shows empty state and add-profile action', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.textContaining('No saved profiles'), findsOneWidget);
    expect(find.text('Add Profile'), findsOneWidget);
  });

  testWidgets('tapping Add Profile opens the login page', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      usersKey: '[{"username":"priya","userId":"u1","displayName":"Priya"}]',
      'lumina_unique_user_id': 'u1',
    });

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Profile'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });
}