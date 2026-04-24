import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeModeKey = 'themeMode';
  final Box _appDataBox;

  ThemeProvider({required Box appBox}) : _appDataBox = appBox {
    _loadThemeMode();
  }

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  /// Whether current active mode is dark based on toggle and system brightness
  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  void _loadThemeMode() {
    final savedValue = _appDataBox.get(_themeModeKey);
    if (savedValue != null) {
      _themeMode = savedValue == 'dark' ? ThemeMode.dark : ThemeMode.light;
    } else {
      _themeMode = ThemeMode.light; // Explicitly defaulting to Light (Organic Atelier) per prompt
    }
  }

  // Toggle dark mode (true = dark, false = light)
  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    await _appDataBox.put(_themeModeKey, isDark ? 'dark' : 'light');
    notifyListeners();
  }
}
