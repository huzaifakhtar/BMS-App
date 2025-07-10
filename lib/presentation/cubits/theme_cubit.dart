import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void setTheme(bool isDark) {
    _isDarkMode = isDark;
    notifyListeners();
  }

  // App theme definitions
  ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    primarySwatch: const MaterialColor(0xFF2563EB, {
      50: Color(0xFFEFF6FF),
      100: Color(0xFFDBEAFE),
      200: Color(0xFFBFDBFE),
      300: Color(0xFF93C5FD),
      400: Color(0xFF60A5FA),
      500: Color(0xFF3B82F6),
      600: Color(0xFF2563EB),
      700: Color(0xFF1D4ED8),
      800: Color(0xFF1E40AF),
      900: Color(0xFF1E3A8A),
    }),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E293B),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF1E293B)),
      bodyMedium: TextStyle(color: Color(0xFF475569)),
      displayLarge: TextStyle(color: Color(0xFF0F172A)),
      displayMedium: TextStyle(color: Color(0xFF1E293B)),
    ),
  );

  ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    primarySwatch: const MaterialColor(0xFF60A5FA, {
      50: Color(0xFFEFF6FF),
      100: Color(0xFFDBEAFE),
      200: Color(0xFFBFDBFE),
      300: Color(0xFF93C5FD),
      400: Color(0xFF60A5FA),
      500: Color(0xFF3B82F6),
      600: Color(0xFF2563EB),
      700: Color(0xFF1D4ED8),
      800: Color(0xFF1E40AF),
      900: Color(0xFF1E3A8A),
    }),
    scaffoldBackgroundColor: const Color(0xFF0F172A),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E293B),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      color: const Color(0xFF1E293B),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFFE2E8F0)),
      bodyMedium: TextStyle(color: Color(0xFF94A3B8)),
      displayLarge: TextStyle(color: Color(0xFFF1F5F9)),
      displayMedium: TextStyle(color: Color(0xFFE2E8F0)),
    ),
  );

  // Helper methods for colors that change based on theme
  Color get primaryColor => _isDarkMode ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
  
  Color get backgroundColor => _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  
  Color get cardColor => _isDarkMode ? const Color(0xFF1E293B) : Colors.white;
  
  Color get textColor => _isDarkMode ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
  
  Color get secondaryTextColor => _isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  
  Color get gaugeBackgroundColor => _isDarkMode ? const Color(0xFF1E293B) : const Color(0xFF3B82F6);
  
  Color get gaugeForegroundColor => _isDarkMode ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
  
  // Additional colors for enhanced theming
  Color get accentColor => _isDarkMode ? const Color(0xFF34D399) : const Color(0xFF059669);
  
  Color get warningColor => _isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  
  Color get errorColor => _isDarkMode ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  
  Color get surfaceColor => _isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
  
  Color get borderColor => _isDarkMode ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
}