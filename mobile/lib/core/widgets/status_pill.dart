import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StatusPill extends StatelessWidget {
  final String status; // 'ON TRACK', 'AHEAD', 'CAUTION', 'DEFICIT'

  const StatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status.toUpperCase()) {
      case 'AHEAD':
        bg = AppColors.inBg;
        fg = AppColors.income;
        icon = Icons.south_west_rounded;
        break;
      case 'ON TRACK':
        bg = AppColors.accentBg;
        fg = AppColors.accent;
        icon = Icons.check_rounded;
        break;
      case 'CAUTION':
        bg = AppColors.amberBg;
        fg = AppColors.amber;
        icon = Icons.warning_amber_rounded;
        break;
      case 'DEFICIT':
      default:
        bg = AppColors.outBg;
        fg = AppColors.expense;
        icon = Icons.warning_rounded;
        break;
    }

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
