import 'package:flutter/material.dart';

/// Curated color tokens tailored for SW-budget.
/// Palette inspired by Ethiopia: Emerald/Teal, Gold/Amber, Deep Obsidian.
abstract class AppColors {
  // Brand Colors
  static const Color primary = Color(0xFF0F766E); // Deep Emerald/Teal
  static const Color primaryLight = Color(0xFF2DD4BF); // Vibrant Mint/Cyan
  static const Color primaryDark = Color(0xFF115E59);
  
  static const Color secondary = Color(0xFFF59E0B); // Ethiopian Gold/Amber
  static const Color secondaryLight = Color(0xFFFBBF24);
  static const Color secondaryDark = Color(0xFFD97706);

  // Background & Surfaces (Dark Theme Default)
  static const Color background = Color(0xFF0B1220); // Deep Obsidian
  static const Color surface = Color(0xFF131D31); // Elevated Card Surface
  static const Color surfaceElevated = Color(0xFF1B2844); // Top-level Modal Surface
  static const Color surfaceLow = Color(0xFF0F172A);

  // Borders & Dividers
  static const Color border = Color(0xFF1E293B);
  static const Color borderSubtle = Color(0xFF172033);
  static const Color borderHighlight = Color(0xFF334155);

  // Text & Typography Colors
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textInverse = Color(0xFF0F172A);

  // Financial Semantics
  static const Color expense = Color(0xFFEF4444); // Bright Red
  static const Color expenseLight = Color(0xFFFCA5A5);
  static const Color expenseSurface = Color(0x26EF4444);

  static const Color income = Color(0xFF10B981); // Emerald Green
  static const Color incomeLight = Color(0xFF6EE7B7);
  static const Color incomeSurface = Color(0x2610B981);

  static const Color transfer = Color(0xFF3B82F6); // Blue
  static const Color transferSurface = Color(0x263B82F6);

  static const Color warning = Color(0xFFF59E0B); // Amber Warning
  static const Color warningSurface = Color(0x26F59E0B);

  // Ethiopian Bank Brand Badges
  static const Color bankCbe = Color(0xFF8B1538); // CBE Purple/Wine
  static const Color bankTelebirr = Color(0xFF0284C7); // Telebirr Sky Blue
  static const Color bankAbyssinia = Color(0xFFF59E0B); // BoA Gold
  static const Color bankCash = Color(0xFF10B981); // Cash Green
}
