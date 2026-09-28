import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  static const _languageKey = 'app_language_v1';
  static const _darkModeKey = 'app_dark_mode_v1';

  Locale _locale;
  bool _darkMode;

  AppPreferences({Locale locale = const Locale('ar'), bool darkMode = false})
    : _locale = locale,
      _darkMode = darkMode;

  Locale get locale => _locale;
  bool get darkMode => _darkMode;
  ThemeMode get themeMode => _darkMode ? ThemeMode.dark : ThemeMode.light;

  static Future<AppPreferences> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppPreferences(
        locale: Locale(prefs.getString(_languageKey) == 'en' ? 'en' : 'ar'),
        darkMode: prefs.getBool(_darkModeKey) ?? false,
      );
    } catch (_) {
      return AppPreferences();
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (languageCode != 'ar' && languageCode != 'en') return;
    if (_locale.languageCode == languageCode) return;
    _locale = Locale(languageCode);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, languageCode);
    } catch (_) {
      // The current session remains usable if device storage is unavailable.
    }
  }

  Future<void> setDarkMode(bool enabled) async {
    if (_darkMode == enabled) return;
    _darkMode = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_darkModeKey, enabled);
    } catch (_) {
      // The current session remains usable if device storage is unavailable.
    }
  }
}
