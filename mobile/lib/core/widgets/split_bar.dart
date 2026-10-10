import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class SplitItem {
  final String label;
  final double amount;
  final Color color;

  const SplitItem({
    required this.label,
    required this.amount,
    required this.color,
  });
}

class SplitBar extends StatelessWidget {
  final List<SplitItem>? items;
  final double? bankAmount;
  final double? mobileMoneyAmount;
  final double? cashAmount;
  final bool? isPrivate;
  final bool isMasked;
  final double height;

  const SplitBar({
    super.key,
    this.items,
    this.bankAmount,
    this.mobileMoneyAmount,
    this.cashAmount,
    this.isPrivate,
    this.isMasked = false,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveItems = items ?? [
      SplitItem(
        label: 'Bank',
        amount: bankAmount ?? 0.0,
        color: AppColors.accent,
      ),
      SplitItem(
        label: 'Mobile money',
        amount: mobileMoneyAmount ?? 0.0,
        color: AppColors.income,
      ),
      SplitItem(
        label: 'Cash',
        amount: cashAmount ?? 0.0,
        color: AppColors.amber,
      ),
    ];

    final effectiveMasked = isPrivate ?? isMasked;
    final total = effectiveItems.fold<double>(0.0, (acc, item) => acc + item.amount);
    final effectiveTotal = total > 0 ? total : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 3-Segment Stacked Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: SizedBox(
            height: height,
            child: Row(
              children: effectiveItems.map((item) {
                final ratio = (item.amount / effectiveTotal).clamp(0.0, 1.0);
                if (ratio <= 0.001) return const SizedBox.shrink();
                return Expanded(
                  flex: (ratio * 1000).toInt(),
                  child: Container(
                    color: item.color,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Legend with percentages & amounts
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: effectiveItems.map((item) {
            final percent = total > 0 ? ((item.amount / total) * 100).toInt() : 0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '${item.label} $percent%',
                  style: const TextStyle(
                    color: AppColors.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  effectiveMasked ? '••••' : 'ETB ${item.amount.toInt()}',
                  style: const TextStyle(
                    color: AppColors.text3,
                    fontSize: 11,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}
