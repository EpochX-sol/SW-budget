import 'package:flutter/material.dart';

/// Exact design tokens from SW-Budget — Mobile UI prototype.html.
abstract class AppColors {
  // Brand & Accent Colors
  static const Color accent = Color(0xFF8AA4FF); // Soft Periwinkle Accent
  static const Color accentBg = Color(0x268AA4FF); // rgba(138,164,255, .15)
  static const Color onAccent = Color(0xFF0A1024);
  static const Color primary = Color(0xFF8AA4FF);
  static const Color primaryLight = Color(0xFF8AA4FF);
  static const Color primaryDark = Color(0xFF6B8AFF);
  static const Color secondary = Color(0xFFFBBF24);
  static const Color secondaryLight = Color(0xFFFBBF24);
  static const Color secondaryDark = Color(0xFFD97706);

  // Backgrounds & Surfaces
  static const Color bg = Color(0xFF080C14); // --bg:#080C14
  static const Color background = Color(0xFF080C14);
  static const Color surface = Color(0xFF101725); // --surface:#101725
  static const Color surface2 = Color(0xFF172033); // --surface2:#172033 (inputs, chips, segments)
  static const Color surface3 = Color(0xFF222D45); // --surface3:#222D45 (elevated borders, tracks)
  static const Color surfaceElevated = Color(0xFF172033);
  static const Color tabBg = Color(0xE0080C14); // rgba(8,12,20,.88)

  // Lines & Borders
  static const Color line = Color(0x12FFFFFF); // rgba(255,255,255,.07)
  static const Color line2 = Color(0x21FFFFFF); // rgba(255,255,255,.13)
  static const Color border = Color(0x12FFFFFF);
  static const Color borderSubtle = Color(0x12FFFFFF);
  static const Color borderHighlight = Color(0x21FFFFFF);

  // Typography Colors
  static const Color text = Color(0xFFEAEEF6); // --text:#EAEEF6
  static const Color textPrimary = Color(0xFFEAEEF6);
  static const Color text2 = Color(0xFFB0B9CC); // --text2:#B0B9CC
  static const Color textSecondary = Color(0xFFB0B9CC);
  static const Color text3 = Color(0xFF8A94AA); // --text3:#8A94AA
  static const Color textMuted = Color(0xFF8A94AA);
  static const Color textInverse = Color(0xFF0A1024);

  // Financial Semantics
  static const Color income = Color(0xFF34D399); // --in:#34D399 (Mint)
  static const Color incomeLight = Color(0xFF34D399);
  static const Color inBg = Color(0x2134D399); // rgba(52,211,153,.13)
  static const Color incomeBg = Color(0x2134D399);
  static const Color incomeSurface = Color(0x2134D399);

  static const Color expense = Color(0xFFFB7185); // --out:#FB7185 (Rose/Coral)
  static const Color expenseLight = Color(0xFFFB7185);
  static const Color outBg = Color(0x21FB7185); // rgba(251,113,133,.13)
  static const Color expenseBg = Color(0x21FB7185);
  static const Color expenseSurface = Color(0x21FB7185);

  static const Color amber = Color(0xFFFBBF24); // --amber:#FBBF24 (Gold/Amber)
  static const Color warning = Color(0xFFFBBF24);
  static const Color amberBg = Color(0x24FBBF24); // rgba(251,191,36,.14)
  static const Color warningSurface = Color(0x24FBBF24);

  static const Color transfer = Color(0xFF94A3B8);
  static const Color transferSurface = Color(0x2194A3B8);

  // Ethiopian Bank Brand Badges
  static const Color bankCbe = Color(0xFF8B1538); // CBE Purple/Wine
  static const Color bankTelebirr = Color(0xFF0284C7); // Telebirr Sky Blue
  static const Color bankAbyssinia = Color(0xFFF59E0B); // BoA Gold
  static const Color bankAwash = Color(0xFF1E3A8A); // Awash Navy Blue
  static const Color bankCbeBirr = Color(0xFFB4234F); // CBE Birr
  static const Color bankCash = Color(0xFF475569); // Physical Cash Slate

  // Hero Gradient
  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF18284A), Color(0xFF111B33), Color(0xFF0D1527)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient primaryGradient = heroGradient;
}
