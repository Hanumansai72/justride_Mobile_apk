import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

/// Returns the global [ThemeData] used by the JustRide app.
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Stack Sans Text',
    textTheme: const TextTheme(
      headlineLarge:
          TextStyle(fontSize: 30, fontWeight: FontWeight.w600, height: 1.15),
      headlineMedium:
          TextStyle(fontSize: 26, fontWeight: FontWeight.w600, height: 1.2),
      titleLarge:
          TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.25),
      titleMedium:
          TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.35),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45),
      bodySmall: TextStyle(fontSize: 13, height: 1.4),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.background,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.primaryLight,
      secondary: AppColors.primary,
      onSecondary: AppColors.background,
      secondaryContainer: AppColors.primaryContainer,
      onSecondaryContainer: AppColors.primaryLight,
      tertiary: AppColors.primaryLight,
      onTertiary: AppColors.onPrimary,
      tertiaryContainer: AppColors.primaryContainer,
      onTertiaryContainer: AppColors.primaryLight,
      surface: AppColors.surface,
      surfaceDim: AppColors.background,
      surfaceBright: AppColors.surfaceElevated,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.backgroundInset,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceElevated,
      surfaceContainerHighest: AppColors.surfaceElevated,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      error: AppColors.errorText,
      onError: AppColors.onPrimary,
      errorContainer: AppColors.errorSurface,
      onErrorContainer: AppColors.errorLight,
      surfaceTint: AppColors.primary,
      inverseSurface: AppColors.surfaceElevated,
      onInverseSurface: AppColors.textPrimary,
      inversePrimary: AppColors.primary,
    ),

    // Material defaults share the same palette as custom screens and the portal.
    canvasColor: AppColors.background,
    dividerColor: AppColors.border,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: AppColors.primary.withValues(alpha: 0.3),
      selectionHandleColor: AppColors.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: TextStyle(color: AppColors.textMuted),
      labelStyle: TextStyle(color: AppColors.textSecondary),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorText)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorText, width: 1.5)),
      errorStyle: TextStyle(color: AppColors.errorText),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600),
      contentTextStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      modalBackgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: AppColors.textMuted,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16))),
      backgroundColor: AppColors.surfaceElevated,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
      actionTextColor: AppColors.primary,
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      minVerticalPadding: 12,
      iconColor: AppColors.primary,
      textColor: AppColors.textPrimary,
      titleTextStyle: TextStyle(
          fontFamily: 'Stack Sans Text',
          fontSize: 16,
          fontWeight: FontWeight.w500),
      subtitleTextStyle: TextStyle(
          fontFamily: 'Stack Sans Text',
          fontSize: 13,
          height: 1.4,
          color: AppColors.textSecondary),
    ),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(48, 48))),
    switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.background
                : AppColors.textMuted)),

    // ── AppBar ───────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.light,
      ),
      centerTitle: false,
      toolbarHeight: 64,
      titleSpacing: 20,
      titleTextStyle: AppTextStyles.headingLarge,
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    ),

    // ── Card ─────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── BottomNavigationBar ──────────────────────────────────────────────────
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textMuted,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    // ── ElevatedButton ───────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
        textStyle: AppTextStyles.button,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
        textStyle: AppTextStyles.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        textStyle: AppTextStyles.button,
      ),
    ),

    // ── Icon ─────────────────────────────────────────────────────────────────
    iconTheme: const IconThemeData(color: AppColors.primary, size: 22),

    // ── Divider ──────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 0,
    ),
  );
}
