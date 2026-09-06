import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/profile_scoped_prefs.dart';
import '../../shared/services/app_icon_service.dart' show setAppIcon;

/// A Riverpod notifier provider that manages and persists the current [ThemeMode].
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// A Riverpod provider for the dark app icon preference.
final appIconProvider = NotifierProvider<AppIconNotifier, bool>(AppIconNotifier.new);

/// A [Notifier] that manages the app's [ThemeMode] and persists the user's
/// dark mode preference to [SharedPreferences].
class ThemeModeNotifier extends Notifier<ThemeMode> {
  bool _loaded = false;

  @override
  ThemeMode build() {
    return ThemeMode.light;
  }

  /// Reads the persisted dark mode preference from [SharedPreferences].
  /// Idempotent: only reads once per app session.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final dark = await ProfileScopedPrefs.getBool('dark_mode');
    state = dark ? ThemeMode.dark : ThemeMode.light;
  }

  /// Sets the current [mode] and persists the choice to [SharedPreferences].
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ProfileScopedPrefs.setBool('dark_mode', mode == ThemeMode.dark);
  }
}

/// A [Notifier] that manages whether the dark app icon is active.
class AppIconNotifier extends Notifier<bool> {
  bool _loaded = false;

  @override
  bool build() {
    // Load the persisted preference on first watch so the settings toggle
    // reflects the live icon instead of defaulting to OFF.
    _load();
    return false;
  }

  /// Reads the persisted dark icon preference from [SharedPreferences].
  /// Idempotent: only reads once per app session.
  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    state = await ProfileScopedPrefs.getBool('dark_app_icon');
  }

  /// Sets whether to use the dark app icon and persists the choice.
  Future<void> setDarkIcon(bool value) async {
    _loaded = true;
    state = value;
    await setAppIcon(value);
    await ProfileScopedPrefs.setBool('dark_app_icon', value);
  }
}
