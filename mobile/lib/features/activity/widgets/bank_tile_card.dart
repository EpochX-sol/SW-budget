import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class BankTileCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? balance;
  final Color brandColor;
  final IconData icon;
  final bool isCandidate;
  final int? messageCount;
  final VoidCallback? onTap;

  const BankTileCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.balance,
    required this.brandColor,
    required this.icon,
    this.isCandidate = false,
    this.messageCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isCandidate
                  ? AppColors.borderHighlight.withOpacity(0.4)
                  : AppColors.border,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Brand Emblem Icon + (Candidate Pill or Status)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: brandColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: brandColor, size: 20),
                  ),
                  if (isCandidate)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primaryLight.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        '+ Add',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Middle: Bank Name & Subtitle
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Bottom: Balance or Candidate message count
              if (isCandidate)
                Text(
                  '${messageCount ?? 0} messages',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Text(
                  balance ?? '0.00 ETB',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: balance == 'Not in total balance'
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    fontSize: balance == 'Not in total balance' ? 11 : 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
