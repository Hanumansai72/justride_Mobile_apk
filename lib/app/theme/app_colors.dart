import 'package:flutter/material.dart';

/// JustRide design-system colour tokens.
/// All raw hex values live here — no other file should hardcode colours.
abstract final class AppColors {
  // ── Backgrounds ────────────────────────────────────────────────────────────
  static const Color background = Color(0xFF080A09);
  static const Color surface = Color(0xFF151917);
  static const Color surfaceElevated = Color(0xFF1C241F);
  static const Color backgroundInset = Color(0xFF101512);

  // ── Brand / Primary ────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF70E8A6);
  static const Color primaryDark = Color(0xFF087C59);
  static const Color primaryContainer = Color(0xFF203B2B);
  static const Color primaryLight = Color(0xFFAAEAC7);
  static const Color onPrimary = background;
  static const Color primaryTranslucent = Color(0x9970E8A6);
  static const Color primarySoft = Color(0x6370E8A6);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFEFF1ED);
  static const Color textSecondary = Color(0xFFBBC3BD);
  static const Color textMuted = Color(0xFF86978A);

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color connected = primary;
  static const Color warning = Color(0xFFFFAB00);
  static const Color error = Color(0xFFD50000);
  static const Color errorText = Color(0xFFFF6B6B);
  static const Color errorLight = Color(0xFFFFB4AB);
  static const Color errorSurface = Color(0xFF2A1718);

  // ── Borders / Dividers ─────────────────────────────────────────────────────
  static const Color border = Color(0xFF27322B);
  static const Color divider = border;

  // ── Transparent helpers ────────────────────────────────────────────────────
  static const Color transparent = Colors.transparent;
}
