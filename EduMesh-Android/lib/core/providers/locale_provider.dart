import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The list of [Locale]s the app supports for translation lookups.
const List<Locale> appSupportedLocales = [
  Locale('en'),
  Locale('hi'),
  Locale('kn'),
];

/// The locale language codes available for user selection.
const List<Map<String, String?>> appLanguageOptions = [
  {'code': 'en', 'label': 'English'},
  {'code': 'hi', 'label': 'Hindi'},
  {'code': 'kn', 'label': 'Kannada'},
  {'code': null, 'label': 'More...'},
];

/// A Riverpod [StateNotifier] that manages the current app [Locale].
///
/// Persists the choice to [SharedPreferences] so it survives restarts.
/// Defaults to `Locale('en')` if no preference is saved.
class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en'));

  static const _prefKey = 'app_locale';

  /// Loads the persisted locale from [SharedPreferences].
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey);
    if (code != null && appSupportedLocales.any((l) => l.languageCode == code)) {
      state = Locale(code);
    }
  }

  /// Sets the current locale and persists it.
  void setLocale(String code) {
    if (code.isEmpty) return;
    state = Locale(code);
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_prefKey, code));
  }
}

/// The Riverpod provider for the current app [Locale].
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});
