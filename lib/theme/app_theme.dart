// ============================================================
// app_theme.dart - Design system for IntelliGuard (Flutter)
// Dark security control-room aesthetic with cyan accent.
// Mirrors src/theme/theme.js from the original React Native app.
// ============================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Backgrounds
  static const bgPrimary = Color(0xFF05060F);
  static const bgSecondary = Color(0xFF0A0E1A);
  static const bgCard = Color(0xFF0F1629);
  static const bgElevated = Color(0xFF141C35);
  static const bgInput = Color(0xFF111827);
  static const bgOverlay = Color(0xB3000000);

  // Borders
  static const borderSubtle = Color(0xFF1E2940);
  static const borderDefault = Color(0xFF243050);
  static const borderBright = Color(0xFF2E3F6B);

  // Text
  static const textPrimary = Color(0xFFE8EEFF);
  static const textSecondary = Color(0xFF8B9AC0);
  static const textMuted = Color(0xFF4A5580);
  static const textInverse = Color(0xFF05060F);

  // Accent - cyan
  static const accentPrimary = Color(0xFF00C8E8);
  static const accentSecondary = Color(0xFF0099BB);
  static const accentGlow = Color(0x2600D4FF);

  // Alerts
  static const fire = Color(0xFFFF4757);
  static const violence = Color(0xFFFF6B35);
  static const restricted = Color(0xFFFFD700);
  static const smoke = Color(0xFF8B9AC0);

  // Status
  static const online = Color(0xFF00FF7F);
  static const offline = Color(0xFFFF4757);
  static const warning = Color(0xFFFFB800);
  static const resolved = Color(0xFF00C8E8);

  static ({Color color, Color bg}) alertStyle(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t.contains('fire')) {
      return (color: fire, bg: fire.withValues(alpha: 0.12));
    }
    if (t.contains('smoke')) {
      return (color: smoke, bg: smoke.withValues(alpha: 0.12));
    }
    if (t.contains('restricted')) {
      return (color: restricted, bg: restricted.withValues(alpha: 0.12));
    }
    if (t.contains('violence')) {
      return (color: violence, bg: violence.withValues(alpha: 0.12));
    }
    return (color: textMuted, bg: textMuted.withValues(alpha: 0.10));
  }

  static ({Color color, Color bg, String label}) statusStyle(String? status) {
    if (status == 'Resolved') {
      return (color: online, bg: online.withValues(alpha: 0.15), label: 'Resolved');
    }
    if (status == 'In Progress') {
      return (color: warning, bg: warning.withValues(alpha: 0.15), label: 'Warning');
    }
    return (color: fire, bg: fire.withValues(alpha: 0.15), label: 'Critical');
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgPrimary,
      primaryColor: AppColors.accentPrimary,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accentPrimary,
        secondary: AppColors.accentSecondary,
        surface: AppColors.bgCard,
        error: AppColors.fire,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgInput,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.accentPrimary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentPrimary,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgCard,
        selectedItemColor: AppColors.accentPrimary,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      dividerColor: AppColors.borderDefault,
    );
  }

  // ── Light theme ──────────────────────────────────────────────────────────────
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    const bg = Color(0xFFF5F7FA);
    const card = Color(0xFFFFFFFF);
    const elevated = Color(0xFFEEF1F8);
    const borderS = Color(0xFFDDE2EE);
    const borderD = Color(0xFFC8CFE0);
    const textPri = Color(0xFF0D1526);
    const textMut = Color(0xFF8B9AC0);
    const accent = AppColors.accentPrimary;
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: AppColors.accentSecondary,
        surface: card,
        error: AppColors.fire,
        onSurface: textPri,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: textPri,
        displayColor: textPri,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: card,
        elevation: 0,
        centerTitle: false,
        foregroundColor: textPri,
        surfaceTintColor: Colors.transparent,
      ),
      cardColor: card,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: borderD),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: borderD),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textMut),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: accent,
        unselectedItemColor: textMut,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        elevation: 8,
      ),
      dividerColor: borderS,
      drawerTheme: const DrawerThemeData(backgroundColor: card),
    );
  }

  static TextStyle mono({double size = 12, Color? color, FontWeight? weight}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, color: color ?? AppColors.textPrimary, fontWeight: weight);
}

extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get cs => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get bgPrimary => isDark ? AppColors.bgPrimary : const Color(0xFFF8FAFC);
  Color get bgSecondary => isDark ? AppColors.bgSecondary : const Color(0xFFEDF2F7);
  Color get bgCard => isDark ? AppColors.bgCard : const Color(0xFFFFFFFF);
  Color get bgElevated => isDark ? AppColors.bgElevated : const Color(0xFFF1F5F9);
  Color get bgInput => isDark ? AppColors.bgInput : const Color(0xFFF1F5F9);

  Color get textPrimary => isDark ? AppColors.textPrimary : const Color(0xFF0F172A);
  Color get textSecondary => isDark ? AppColors.textSecondary : const Color(0xFF475569);
  Color get textMuted => isDark ? AppColors.textMuted : const Color(0xFF94A3B8);

  Color get borderSubtle => isDark ? AppColors.borderSubtle : const Color(0xFFE2E8F0);
  Color get borderDefault => isDark ? AppColors.borderDefault : const Color(0xFFCBD5E1);
}
