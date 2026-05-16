import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core/theme/lumina_lite_theme.dart';
import 'features/auth/presentation/welcome_page.dart';
import 'features/auth/data/auth_service.dart';
import 'widgets/connection_gate.dart';
import 'pages/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check auth state
  final authService = AuthService();
  final userId = await authService.getUniqueUserId();
  final bool isLoggedIn = userId != null;

  runApp(
    ProviderScope(
      child: LuminaApp(isLoggedIn: isLoggedIn),
    ),
  );
}

class LuminaApp extends StatelessWidget {
  final bool isLoggedIn;
  const LuminaApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 800),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'Edu-Mesh Scholar',
          theme: LuminaLiteTheme.lightTheme,
          darkTheme: LuminaLiteTheme.darkTheme,
          themeMode: ThemeMode.light,
          debugShowCheckedModeBanner: false,
          home: isLoggedIn 
            ? const ConnectionGate(child: AppShell()) 
            : const WelcomePage(),
        );
      },
    );
  }
}
