// ============================================================
// theme_provider.dart — Light/Dark theme state + persistence
// Uses SharedPreferences to save the user's choice across
// restarts. Exposes themeMode for MaterialApp.
// ============================================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'ig_theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  bool get isLight => _mode == ThemeMode.light;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == 'light') {
      _mode = ThemeMode.light;
      notifyListeners();
    }
  }

  Future<void> setLight() async {
    if (_mode == ThemeMode.light) return;
    _mode = ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, 'light');
  }

  Future<void> setDark() async {
    if (_mode == ThemeMode.dark) return;
    _mode = ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, 'dark');
  }

  Future<void> toggle() async {
    if (_mode == ThemeMode.light) {
      await setDark();
    } else {
      await setLight();
    }
  }
}
