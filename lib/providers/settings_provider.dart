import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan aplikasi (mode tema) — disimpan di perangkat.
class SettingsProvider extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode themeMode = ThemeMode.system;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_key)) {
      case 'light':
        themeMode = ThemeMode.light;
        break;
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      default:
        themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  String get themeLabel => switch (themeMode) {
        ThemeMode.light => 'Terang',
        ThemeMode.dark => 'Gelap',
        ThemeMode.system => 'Ikuti sistem',
      };
}
