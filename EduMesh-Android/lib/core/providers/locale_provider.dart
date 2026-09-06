import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/profile_scoped_prefs.dart';

/// The list of [Locale]s the app supports for translation lookups.
const List<Locale> appSupportedLocales = [
  Locale('en'),
  Locale('hi'),
  Locale('kn'),
  Locale('fr'),
  Locale('ta'),
  Locale('te'),
];

/// The locale language codes available for user selection.
const List<Map<String, String?>> appLanguageOptions = [
  {'code': 'en', 'label': 'English'},
  {'code': 'hi', 'label': 'हिन्दी'},
  {'code': 'kn', 'label': 'ಕನ್ನಡ'},
  {'code': 'fr', 'label': 'Français'},
  {'code': 'ta', 'label': 'தமிழ்'},
  {'code': 'te', 'label': 'తెలుగు'},
];

/// Persists the choice to [SharedPreferences] so it survives restarts.
/// Defaults to `Locale('en')` if no preference is saved.
class LocaleNotifier extends Notifier<Locale> {
  static const _prefKey = 'app_locale';
  bool _loaded = false;

  /// Loads the persisted locale from [SharedPreferences].
  ///
  /// Safe to call multiple times: only the first call reads storage.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final code = await ProfileScopedPrefs.getString(_prefKey);
    if (code != null && appSupportedLocales.any((l) => l.languageCode == code)) {
      state = Locale(code);
    }
  }

  /// Sets the current locale and persists it.
  void setLocale(String code) {
    if (code.isEmpty) return;
    state = Locale(code);
    ProfileScopedPrefs.setString(_prefKey, code);
  }

  @override
  Locale build() => const Locale('en');
}

/// The Riverpod provider for the current app [Locale].
final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
