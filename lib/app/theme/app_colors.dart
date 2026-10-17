import 'package:flutter/material.dart';

/// JustRide design-system colour tokens.
/// All raw hex values live here — no other file should hardcode colours.
abstract final class AppColors {
  // ── Backgrounds ────────────────────────────────────────────────────────────
  static const Color background = Color(0xFF0B100D);
  static const Color surface = Color(0xFF141A16);
  static const Color surfaceElevated = Color(0xFF1A211C);
  static const Color backgroundInset = Color(0xFF101812);

  // ── Brand / Primary ────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF34D399);
  static const Color primaryDark = Color(0xFF087C59);
  static const Color primaryContainer = Color(0xFF004B1E);
  static const Color primaryLight = Color(0xFF6EE7B7);
  static const Color onPrimary = background;
  static const Color primaryTranslucent = Color(0x9934D399);
  static const Color primarySoft = Color(0x6334D399);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF5F7F5);
  static const Color textSecondary = Color(0xFFAAB5AD);
  static const Color textMuted = Color(0xFF86978A);

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color connected = primary;
  static const Color warning = Color(0xFFFFAB00);
  static const Color error = Color(0xFFD50000);
  static const Color errorText = Color(0xFFFF6B6B);
  static const Color errorLight = Color(0xFFFFB4AB);
  static const Color errorSurface = Color(0xFF2A1718);

  // ── Borders / Dividers ─────────────────────────────────────────────────────
  static const Color border = Color(0xFF354438);
  static const Color divider = border;

  // ── Transparent helpers ────────────────────────────────────────────────────
  static const Color transparent = Colors.transparent;
}
