import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'ta': 'தமிழ்',
    'hi': 'हिन्दी',
  };

  Future<void> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code  = prefs.getString('language_code') ?? 'en';
    _locale     = Locale(code);
    notifyListeners();
  }

  Future<void> setLocale(String languageCode) async {
    if (!supportedLanguages.containsKey(languageCode)) return;
    _locale = Locale(languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', languageCode);
    notifyListeners();
  }

  String get currentLanguageName =>
    supportedLanguages[_locale.languageCode] ?? 'English';
}
