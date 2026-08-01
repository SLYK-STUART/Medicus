import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Clean clinical palette — deep trustworthy blue as primary, soft blue-grey
/// surfaces, high-contrast text. Kept restrained (few accent colors) since
/// this is a healthcare app — calm over flashy.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF0B5FA5); // deep clinical blue
  static const primaryLight = Color(0xFF4A8FCB);
  static const primaryDark = Color(0xFF073E6D);
  static const secondary = Color(0xFF2E9E8F); // muted teal — used sparingly for positive/success states
  static const surface = Color(0xFFF7FAFC); // near-white, faint blue tint
  static const surfaceVariant = Color(0xFFE8F0F7);
  static const error = Color(0xFFC2410C); // warm red-orange, less alarming than pure red
  static const critical = Color(0xFFB91C1C); // reserved specifically for priority='critical' UI
  static const urgent = Color(0xFFD97706);
  static const textPrimary = Color(0xFF102A43);
  static const textSecondary = Color(0xFF486581);
}

// Type pairing:
// — Plus Jakarta Sans for headlines/titles: a geometric sans with slightly
//   rounded terminals, reads as modern and approachable without losing
//   professionalism — offsets how clinical the blue palette can otherwise feel.
// — IBM Plex Sans for body/labels: built for dense technical and data-heavy
//   interfaces, stays highly legible at small sizes (queue lists, timestamps,
//   status chips) and carries a precise, trustworthy tone fitting for health data.
final _displayFont = GoogleFonts.plusJakartaSansTextTheme();
final _bodyFont = GoogleFonts.ibmPlexSansTextTheme();

final TextTheme _appTextTheme = _bodyFont.copyWith(
  headlineMedium: _displayFont.headlineMedium?.copyWith(
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  ),
  headlineSmall: _displayFont.headlineSmall?.copyWith(
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  ),
  titleLarge: _displayFont.titleLarge?.copyWith(
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  ),
  titleMedium: _displayFont.titleMedium?.copyWith(
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  ),
  bodyLarge: _bodyFont.bodyLarge?.copyWith(
    color: AppColors.textPrimary,
    height: 1.4,
  ),
  bodyMedium: _bodyFont.bodyMedium?.copyWith(
    color: AppColors.textSecondary,
    height: 1.4,
  ),
  labelLarge: _bodyFont.labelLarge?.copyWith(
    fontWeight: FontWeight.w600,
  ),
);

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.surface,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    surface: Colors.white,
    error: AppColors.error,
    brightness: Brightness.light,
  ),

  textTheme: _appTextTheme,

  appBarTheme: AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: AppColors.textPrimary,
    elevation: 0,
    scrolledUnderElevation: 1,
    centerTitle: false,
    titleTextStyle: _displayFont.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
  ),

  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: _bodyFont.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),

  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.primary,
      side: const BorderSide(color: AppColors.primary, width: 1.5),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: _bodyFont.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
  ),

  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      textStyle: _bodyFont.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceVariant.withValues(alpha: 0.5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.error, width: 1.5),
    ),
    labelStyle: _bodyFont.bodyMedium?.copyWith(color: AppColors.textSecondary),
  ),

  cardTheme: CardThemeData(
    elevation: 0,
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: AppColors.surfaceVariant, width: 1),
    ),
    margin: const EdgeInsets.symmetric(vertical: 6),
  ),

  listTileTheme: ListTileThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    tileColor: Colors.white,
  ),

  dividerTheme: const DividerThemeData(color: AppColors.surfaceVariant, thickness: 1),

  chipTheme: ChipThemeData(
    backgroundColor: AppColors.surfaceVariant,
    labelStyle: _bodyFont.labelLarge?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),

  snackBarTheme: SnackBarThemeData(
    backgroundColor: AppColors.textPrimary,
    contentTextStyle: _bodyFont.bodyMedium?.copyWith(color: Colors.white),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
);

/// Shared status→color mapping, used across appointment/queue status
/// displays so the same status always reads the same color everywhere.
Color statusColor(String status) {
  switch (status) {
    case 'booked':
      return AppColors.textSecondary;
    case 'checked_in':
    case 'waiting':
      return AppColors.primary;
    case 'called':
      return AppColors.urgent;
    case 'in_consultation':
      return AppColors.secondary;
    case 'completed':
      return const Color(0xFF15803D);
    case 'skipped':
      return AppColors.error;
    case 'paused':
      return AppColors.urgent;
    default:
      return AppColors.textSecondary;
  }
}

Color priorityColor(String priority) {
  switch (priority) {
    case 'critical':
      return AppColors.critical;
    case 'urgent':
      return AppColors.urgent;
    default:
      return AppColors.textSecondary;
  }
}