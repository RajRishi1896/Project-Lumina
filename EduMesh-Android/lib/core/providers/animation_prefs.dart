import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global user preference for UI animations (settings toggle).
///
/// OFF is the default: Lumina ships fast and instant; users opt in to
/// transitions. This preference never overrides the platform reduced-motion
/// accessibility flag — callers must combine [enabled] with
/// `MediaQuery.disableAnimationsOf(context)` (see LuminaTransitions).
class AnimationPrefs extends ChangeNotifier {
  static final AnimationPrefs _instance = AnimationPrefs._internal();
  factory AnimationPrefs() => _instance;
  AnimationPrefs._internal();

  /// SharedPreferences key; also used by tests to seed the mock store.
  static const String prefKey = 'animations_enabled';

  bool _enabled = false;
  bool _loaded = false;

  /// Whether supported UI animations should run. Defaults to false.
  bool get enabled => _enabled;

  /// Loads the persisted preference. Safe to call multiple times.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(prefKey) ?? false;
    notifyListeners();
  }

  /// Sets the preference and persists it across restarts.
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, value);
  }

  /// Test hook: resets the singleton so the next [load] re-reads storage.
  @visibleForTesting
  void resetForTest() {
    _enabled = false;
    _loaded = false;
  }
}
