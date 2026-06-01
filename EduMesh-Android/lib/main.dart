import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// Ensure these imports match your project structure exactly
import 'package:edumesh_android/core/theme/lumina_lite_theme.dart';
import 'package:edumesh_android/core/theme/theme_provider.dart'; 
import 'package:edumesh_android/features/auth/presentation/welcome_page.dart';
import 'package:edumesh_android/features/auth/data/auth_service.dart';
import 'package:edumesh_android/widgets/connection_gate.dart';
import 'package:edumesh_android/pages/app_shell.dart';
import 'package:edumesh_android/core/models/resource_model.dart';
import 'package:edumesh_android/shared/services/mock_data_service.dart';

void initializeAppData() {
  MockDataService.seedIncomingResources([
    ResourceModel(id: '1', title: 'Calculus Textbook', subject: 'Math', grade: '12', type: ResourceType.textbook),
    ResourceModel(id: '2', title: 'Physics Notes', subject: 'Science', grade: '11', type: ResourceType.notes),
    ResourceModel(id: '3', title: 'Organic Chem Video', subject: 'Science', grade: '12', type: ResourceType.videos),
    ResourceModel(id: '4', title: 'Math 2024 PYQ', subject: 'Math', grade: '12', type: ResourceType.pyq),
    ResourceModel(id: '5', title: 'Bio PYQ 2025', subject: 'Science', grade: '12', type: ResourceType.pyq),
  ]);
}

void main() async { 
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    initializeAppData();
  }

  final authService = AuthService();
  final userId = await authService.getUniqueUserId();
  final bool isLoggedIn = userId != null;

  runApp(
    ProviderScope(
      child: LuminaApp(isLoggedIn: isLoggedIn),
    ),
  );
}

class LuminaApp extends ConsumerWidget {
  final bool isLoggedIn;
  const LuminaApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return ScreenUtilInit(
      designSize: const Size(360, 800),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'Edu-Mesh Scholar',
          theme: LuminaLiteTheme.lightTheme,
          darkTheme: LuminaLiteTheme.darkTheme,
          themeMode: themeMode, 
          debugShowCheckedModeBanner: false,
          home: isLoggedIn 
            ? const ConnectionGate(child: AppShell()) 
            : const WelcomePage(),
        );
      },
    );
  }
}