import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/services/app_icon_service.dart';

/// A Riverpod provider that always resolves to [ThemeMode.light] as the default.
final initialThemeProvider = Provider<ThemeMode>((ref) => ThemeMode.light);

/// A Riverpod notifier provider that manages and persists the current [ThemeMode].
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// A Riverpod provider for the dark app icon preference.
final appIconProvider = NotifierProvider<AppIconNotifier, bool>(AppIconNotifier.new);

/// A [Notifier] that manages the app's [ThemeMode] and persists the user's
/// dark mode preference to [SharedPreferences].
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    return ref.watch(initialThemeProvider);
  }

  /// Toggles between [ThemeMode.light] and [ThemeMode.dark] and persists the choice.
  Future<void> toggle() async {
    final newMode = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    state = newMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', newMode == ThemeMode.dark);
  }

  /// Sets the current [mode] and persists the choice to [SharedPreferences].
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', mode == ThemeMode.dark);
  }
}

/// A [Notifier] that manages whether the dark app icon is active.
class AppIconNotifier extends Notifier<bool> {
  @override
  bool build() {
    return false;
  }

  /// Sets whether to use the dark app icon and persists the choice.
  Future<void> setDarkIcon(bool value) async {
    state = value;
    await AppIconService.setAppIcon(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_app_icon', value);
  }
}
