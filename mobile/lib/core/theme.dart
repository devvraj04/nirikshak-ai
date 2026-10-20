import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Base Palette
  static const Color baseBackground = Color(0xFFFAF8F2); // Warm glacier mist base
  static const Color auraBg = baseBackground;           // Aura background alias
  static const Color slate900 = Color(0xFF0F172A);       // Deep slate header/buttons
  static const Color slate800 = Color(0xFF1E293B);       // Slate surface
  static const Color slate700 = Color(0xFF334155);       // Slate borders / muted text
  static const Color slate600 = Color(0xFF475569);       // Slate secondary text
  static const Color slate500 = Color(0xFF64748B);       // Subtle captions
  static const Color slate400 = Color(0xFF94A3B8);       // Hint text
  static const Color slate300 = Color(0xFFCBD5E1);       // Light borders / dots
  static const Color slate200 = Color(0xFFE2E8F0);       // Light borders
  static const Color slate100 = Color(0xFFF1F5F9);       // Pill backgrounds
  static const Color slate50 = Color(0xFFF8FAFC);        // Very light slate background
  static const Color textMain = Color(0xFF1A202C);       // Primary dark text

  // Accent Colors
  static const Color emerald500 = Color(0xFF10B981);     // Emerald primary
  static const Color emerald400 = Color(0xFF34D399);     // Vibrant emerald highlight
  static const Color emerald300 = Color(0xFF6EE7B7);     // Soft emerald text
  static const Color emerald600 = Color(0xFF059669);     // Rich emerald icon
  static const Color emerald700 = Color(0xFF047857);     // Dark emerald
  static const Color emerald800 = Color(0xFF065F46);     // Emerald badge text
  static const Color emerald100 = Color(0xFFD1FAE5);     // Emerald badge fill
  static const Color emerald50 = Color(0xFFECFDF5);      // Emerald tint background
  static const Color emerald200 = Color(0xFFA7F3D0);     // Emerald badge border

  // Aura Atmospheric Blend Colors
  static const Color auraCyan = Color(0xFF4DD2FF);       // 77, 210, 255
  static const Color auraMint = Color(0xFF35E6C0);       // 53, 230, 192
  static const Color auraIndigo = Color(0xFF5B6EF5);     // 91, 110, 245

  // Semantic Status Colors
  static const Color successGreen = Color(0xFF10B981);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color warningAmber = Color(0xFFD97706);
  static const Color warningAmberLight = Color(0xFFFEF3C7);
  static const Color infoBlue = Color(0xFF2563EB);
  static const Color infoBlueLight = Color(0xFFEFF6FF);

  // Glassmorphic tokens
  static const Color glassFill = Color(0xB8FFFFFF);      // rgba(255, 255, 255, 0.72)
  static const Color glassBorder = Color(0xD9FFFFFF);    // rgba(255, 255, 255, 0.85)
  static const Color glassShadow = Color(0x121F2687);    // rgba(31, 38, 135, 0.07)

  // Legacy compatibility aliases
  static const Color primaryBlue = slate900;
  static const Color accentCyan = emerald500;
  static const Color cardDark = slate800;
  static const Color surfaceDark = slate900;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: baseBackground,
      primaryColor: slate900,
      colorScheme: const ColorScheme.light(
        primary: slate900,
        secondary: emerald500,
        surface: Colors.white,
        error: dangerRed,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme).apply(
        bodyColor: textMain,
        displayColor: slate900,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: slate900),
        titleTextStyle: TextStyle(color: slate900, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: emerald500,
          foregroundColor: slate900,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  static ThemeData get darkTheme => lightTheme;
}
