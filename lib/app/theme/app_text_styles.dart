import 'package:flutter/material.dart';
import 'app_colors.dart';

/// The customer's Stack Sans typeface is bundled for offline use in the app.
abstract final class AppTextStyles {
  // ── Display ────────────────────────────────────────────────────────────────
  static TextStyle get displayLarge => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 32,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      );

  static TextStyle get displayMedium => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 26,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
      );

  // ── Headings ───────────────────────────────────────────────────────────────
  static TextStyle get headingLarge => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 22,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  static TextStyle get headingMedium => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  static TextStyle get headingSmall => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  // ── Body ───────────────────────────────────────────────────────────────────
  static TextStyle get bodyLarge => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get bodySmall => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  // ── Labels ─────────────────────────────────────────────────────────────────
  static TextStyle get labelLarge => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.5,
      );

  static TextStyle get labelMedium => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        letterSpacing: 0.4,
      );

  static TextStyle get labelSmall => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 10,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
        letterSpacing: 0.6,
      );

  // ── Brand ──────────────────────────────────────────────────────────────────
  static TextStyle get brandLogo => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      );

  static TextStyle get brandTagline => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 9,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        letterSpacing: 2.5,
      );

  // ── Primary Accent ─────────────────────────────────────────────────────────
  static TextStyle get accentLarge => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      );

  static TextStyle get accentMedium => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.primary,
      );

  // ── CTA / Button ───────────────────────────────────────────────────────────
  static TextStyle get button => TextStyle(
        fontFamily: 'Stack Sans Text',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.background,
        letterSpacing: 0,
      );
}
