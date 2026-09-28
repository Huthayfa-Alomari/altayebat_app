import 'package:altayebat_app/settings/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('language and dark mode persist across app launches', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await AppPreferences.load();
    expect(first.locale.languageCode, 'ar');
    expect(first.themeMode, ThemeMode.light);

    await first.setLanguage('en');
    await first.setDarkMode(true);

    final restored = await AppPreferences.load();
    expect(restored.locale.languageCode, 'en');
    expect(restored.themeMode, ThemeMode.dark);
  });
}
