import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class ExportStatementSheet extends StatefulWidget {
  final Function(String period, String format)? onGenerate;

  const ExportStatementSheet({super.key, this.onGenerate});

  static void show(BuildContext context, {Function(String period, String format)? onGenerate}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => ExportStatementSheet(onGenerate: onGenerate),
    );
  }

  @override
  State<ExportStatementSheet> createState() => _ExportStatementSheetState();
}

class _ExportStatementSheetState extends State<ExportStatementSheet> {
  String _period = 'cycle';
  String _format = 'pdf';

  final List<List<String>> _periods = [
    ['cycle', 'This cycle'],
    ['30', 'Last 30 days'],
    ['90', 'Last 3 months'],
    ['ytd', 'Year to date'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Export statement', style: AppTypography.titleLarge),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.text2),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Period Selector
          Text('Period', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line, width: 1.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _period,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                items: _periods.map((p) {
                  return DropdownMenuItem(value: p[0], child: Text(p[1], style: AppTypography.bodyMedium));
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _period = val);
                },
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Format Segment
          Text('Format', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _segButton('PDF · for banks & embassies', _format == 'pdf', () {
                    setState(() => _format = 'pdf');
                  }),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _segButton('CSV · spreadsheet', _format == 'csv', () {
                    setState(() => _format = 'csv');
                  }),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Security banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Generated on this device. Nothing is uploaded to external clouds.',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.text2),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onGenerate?.call(_period, _format);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Statement generated in ${_format.toUpperCase()} format.')),
              );
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  Widget _segButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.text : AppColors.text2,
          ),
        ),
      ),
    );
  }
}
