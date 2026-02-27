import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  bool _isDarkMode = true;
  bool get isDarkMode => _isDarkMode;

  ThemeService() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
    notifyListeners();
  }

  ThemeData get themeData {
    return _isDarkMode ? _auraDarkTheme : _auraLightTheme;
  }

  static final ThemeData _auraDarkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0D0F14),
    primaryColor: const Color(0xFF4F8CFF),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF4F8CFF),
      secondary: Color(0xFF7C5CFF),
      surface: Color(0xFF151821),
      onSurface: Colors.white,
      surfaceContainerHighest: Color(0xFF1C1F2A),
      error: Color(0xFFFF5A5F),
    ),
    cardTheme: CardTheme(
      color: const Color(0xFF1C1F2A),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF262A35),
      thickness: 1,
    ),
  );

  static final ThemeData _auraLightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF8F9FD),
    primaryColor: const Color(0xFF4F8CFF),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF4F8CFF),
      secondary: Color(0xFF7C5CFF),
      surface: Colors.white,
      onSurface: Color(0xFF0D0F14),
      surfaceContainerHighest: Color(0xFFF0F2F8),
      error: Color(0xFFFF5A5F),
    ),
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: Color(0xFF0D0F14)),
      titleTextStyle: TextStyle(color: Color(0xFF0D0F14), fontSize: 20, fontWeight: FontWeight.bold),
    ),
  );
}
