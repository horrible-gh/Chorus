import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light {
    const seed = Color(0xFF2F6F73);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: seed),
      inputDecorationTheme: _inputDecorationTheme,
      useMaterial3: true,
    );
  }

  static ThemeData get dark {
    const seed = Color(0xFF6AA7A8);
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      inputDecorationTheme: _inputDecorationTheme,
      useMaterial3: true,
    );
  }

  static const _inputDecorationTheme = InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
  );
}
