import 'package:flutter/material.dart';

import 'screens/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LyricFlowApp());
}

class LyricFlowApp extends StatelessWidget {
  const LyricFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFF0D0E16);
    const accent = Color(0xFFC9ABFF);
    return MaterialApp(
      title: 'LyricFlow',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: base,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          surface: Color(0xFF171923),
          onSurface: Color(0xFFF3F0FA),
          secondary: Color(0xFF9BDAD2),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: base, elevation: 0),
        cardTheme: CardThemeData(color: const Color(0xFF191C29)),
      ),
      home: const LibraryScreen(),
    );
  }
}
