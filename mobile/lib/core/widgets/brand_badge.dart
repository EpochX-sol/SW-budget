import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class BrandBadge extends StatelessWidget {
  final String? provider;
  final String? institution;
  final double size;

  const BrandBadge({
    super.key,
    this.provider,
    this.institution,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final raw = (institution ?? provider ?? '').toUpperCase();

    Color bgColor = AppColors.accent;
    Color fgColor = Colors.white;
    String short = raw.isNotEmpty ? (raw.length > 3 ? raw.substring(0, 3) : raw) : 'ETB';

    if (raw.contains('CBEBIRR')) {
      bgColor = const Color(0xFF8B2684);
      fgColor = Colors.white;
      short = 'Birr';
    } else if (raw.contains('CBE')) {
      bgColor = const Color(0xFF6B227B);
      fgColor = Colors.white;
      short = 'CBE';
    } else if (raw.contains('TELEBIRR') || raw.contains('TB') || raw == '127') {
      bgColor = const Color(0xFF0091DA);
      fgColor = Colors.white;
      short = 'Tb';
    } else if (raw.contains('BOA') || raw.contains('ABYSSINIA') || raw.contains('APOLLO')) {
      bgColor = const Color(0xFFF37021);
      fgColor = Colors.white;
      short = 'BoA';
    } else if (raw.contains('AWASH') || raw.contains('AW')) {
      bgColor = const Color(0xFF005B94);
      fgColor = Colors.white;
      short = 'Aw';
    } else if (raw.contains('CASH')) {
      bgColor = AppColors.amber;
      fgColor = const Color(0xFF080C14);
      short = 'ETB';
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        short,
        style: TextStyle(
          color: fgColor,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.35,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}
