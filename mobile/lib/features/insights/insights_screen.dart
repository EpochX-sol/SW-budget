import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/backup/backup_export_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../activity/activity_providers.dart';
import '../plan/plan_providers.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int? _selectedDay;

  void _showBackupPasswordDialog(BuildContext context) {
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Encrypt Backup Vault', style: AppTypography.titleLarge),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a strong passphrase to encrypt your .swbackup archive using hardware-derived AES-256-GCM.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: AppTypography.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Vault Password',
                filled: true,
                fillColor: AppColors.surfaceElevated,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () async {
              final pwd = passwordController.text.trim();
              if (pwd.length < 4) return;
              Navigator.of(dialogCtx).pop();

              try {
                final service = await ref.read(backupExportServiceProvider.future);
                await service.createEncryptedBackupFile(password: pwd);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Encrypted .swbackup archive generated and shared.')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Backup export failed: $e')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryLight),
            child: const Text('Encrypt & Export'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeToSpend = ref.watch(safeToSpendProvider);
    final transactionsAsync = ref.watch(transactionsProvider);
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final monthName = DateFormat('MMMM yyyy').format(now);

    final transactions = transactionsAsync.asData?.value ?? [];

    // Calculate real fee sum
    double totalFees = 0.0;
    final Map<int, double> dailySpend = {};

    for (final t in transactions) {
      final type = (t['type'] as String? ?? '').toLowerCase();
      final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
      final occurred = DateTime.tryParse(t['occurred_at'] as String? ?? '');

      if (type == 'fee') {
        totalFees += amount;
      }

      if (type == 'expense' && occurred != null && occurred.year == now.year && occurred.month == now.month) {
        dailySpend[occurred.day] = (dailySpend[occurred.day] ?? 0.0) + amount;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Analytics & Forecasting', style: AppTypography.titleLarge),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Burn-down Forecast Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.surfaceElevated, AppColors.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.borderHighlight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('MONTHLY FORECAST',
                            style: AppTypography.labelSmall.copyWith(
                                color: AppColors.primaryLight, fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.incomeSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Projected On Track',
                            style: AppTypography.labelSmall.copyWith(
                                color: AppColors.incomeLight, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${safeToSpend.safeToday.toStringAsFixed(2)} ETB',
                      style: AppTypography.displayMedium.copyWith(
                          fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    Text('Safe daily burn rate for remainder of $monthName',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ForecastStat(
                            label: 'Total Budget',
                            value: '${safeToSpend.totalBudget.toStringAsFixed(0)} ETB'),
                        _ForecastStat(
                            label: 'Current Spend',
                            value: '${safeToSpend.spentSoFar.toStringAsFixed(0)} ETB'),
                        _ForecastStat(
                            label: 'Days Left',
                            value: '${safeToSpend.daysRemaining} days'),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Money Calendar Heatmap
              Text('Money Calendar ($monthName)', style: AppTypography.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Daily expense density calculated from verified ledger transactions.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    // Day of week headers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                          .map((d) => SizedBox(
                                width: 34,
                                child: Text(
                                  d,
                                  textAlign: TextAlign.center,
                                  style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 10),

                    // Calendar Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: daysInMonth,
                      itemBuilder: (context, index) {
                        final day = index + 1;
                        final isSelected = _selectedDay == day;
                        final isToday = day == now.day;
                        final spend = dailySpend[day] ?? 0.0;

                        Color heatColor = AppColors.surfaceElevated;
                        if (spend > safeToSpend.safeToday * 1.5) {
                          heatColor = AppColors.expense.withOpacity(0.5);
                        } else if (spend > 0) {
                          heatColor = AppColors.primary.withOpacity(0.35);
                        } else if (day < now.day) {
                          heatColor = AppColors.surfaceElevated.withOpacity(0.6);
                        }

                        return GestureDetector(
                          onTap: () => setState(() => _selectedDay = day),
                          child: Container(
                            decoration: BoxDecoration(
                              color: heatColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primaryLight
                                    : isToday
                                        ? AppColors.secondaryLight
                                        : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$day',
                                style: AppTypography.labelSmall.copyWith(
                                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                  color: isToday ? AppColors.secondaryLight : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    if (_selectedDay != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Day $_selectedDay: Total Spend = ${(dailySpend[_selectedDay!] ?? 0.0).toStringAsFixed(2)} ETB',
                        style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primaryLight, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Bank Tariff & Transfer Fees Audit
              Text('Hidden Fees & Tariff Audit', style: AppTypography.titleMedium),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.receipt_rounded, color: AppColors.warning, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bank & Telebirr Tariffs YTD',
                              style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                          Text('ATM, transfer, and service fees detected',
                              style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Text(
                      '${totalFees.toStringAsFixed(2)} ETB',
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Data Sovereignty & Export Actions
              Text('Data Sovereignty & Backups', style: AppTypography.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final service = await ref.read(backupExportServiceProvider.future);
                          await service.exportTransactionsCsv();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('CSV export failed: $e')),
                          );
                        }
                      },
                      icon: const Icon(Icons.table_chart_outlined, size: 18),
                      label: const Text('Export CSV'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _showBackupPasswordDialog(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryLight,
                        foregroundColor: AppColors.textInverse,
                      ),
                      icon: const Icon(Icons.lock_outline_rounded, size: 18),
                      label: const Text('Create Backup'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForecastStat extends StatelessWidget {
  final String label;
  final String value;

  const _ForecastStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Text(value, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
