import 'package:flutter/material.dart';

/// JustRide design-system colour tokens.
/// All raw hex values live here — no other file should hardcode colours.
abstract final class AppColors {
  // ── Backgrounds ────────────────────────────────────────────────────────────
  static const Color background = Color(0xFF0D0D0D);
  static const Color surface = Color(0xFF1C1C1C);
  static const Color surfaceElevated = Color(0xFF242424);

  // ── Brand / Primary ────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF00C853);
  static const Color primaryDark = Color(0xFF009624);
  static const Color primaryContainer = Color(0xFF0A2E16);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9E9E9E);
  static const Color textMuted = Color(0xFF616161);

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color connected = Color(0xFF00C853);
  static const Color warning = Color(0xFFFFAB00);
  static const Color error = Color(0xFFD50000);

  // ── Borders / Dividers ─────────────────────────────────────────────────────
  static const Color border = Color(0xFF2C2C2C);
  static const Color divider = Color(0xFF222222);

  // ── Transparent helpers ────────────────────────────────────────────────────
  static const Color transparent = Colors.transparent;
}
