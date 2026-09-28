import 'package:flutter/widgets.dart';

class AppLanguage {
  AppLanguage._();

  static bool isEnglish(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'en';

  static String text(BuildContext context, String arabic, String english) =>
      isEnglish(context) ? english : arabic;
}
