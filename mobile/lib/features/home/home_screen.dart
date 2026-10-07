import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/security/auth_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../activity/activity_providers.dart';
import '../plan/plan_providers.dart';
import 'widgets/safe_to_spend_gauge.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final safeToSpend = ref.watch(safeToSpendProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final user = authState.userProfile;
    final displayName = user?['display_name'] as String? ?? 'User';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selam, $displayName', style: AppTypography.titleLarge),
            Text('Financial Health Overview',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary),
            tooltip: 'Lock Ledger',
            onPressed: () {
              ref.read(authStateProvider.notifier).lockApp();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.textSecondary),
            tooltip: 'Sign Out',
            onPressed: () {
              ref.read(authStateProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dynamic Safe-to-Spend Animated Ring Gauge
              SafeToSpendGauge(summary: safeToSpend),

              const SizedBox(height: 24),

              // Connected Providers
              Text('Linked Accounts', style: AppTypography.titleMedium),
              const SizedBox(height: 12),
              accountsAsync.when(
                data: (accounts) {
                  if (accounts.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_outlined, color: AppColors.textMuted),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No bank accounts linked yet. Incoming transactions will auto-register your CBE or Telebirr account.',
                              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: accounts.map((acc) {
                      final provider = (acc['provider'] as String? ?? 'ACCOUNT').toUpperCase();
                      final name = acc['name'] as String? ?? 'Bank Account';
                      final mask = acc['account_mask'] as String? ?? '••••';
                      final balanceVal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;
                      final balanceStr = '${balanceVal.toStringAsFixed(2)} ETB';

                      Color brandColor = AppColors.primary;
                      IconData brandIcon = Icons.account_balance_rounded;

                      if (provider.contains('TELEBIRR') || provider == '127') {
                        brandColor = AppColors.bankTelebirr;
                        brandIcon = Icons.phone_android_rounded;
                      } else if (provider.contains('CBE')) {
                        brandColor = AppColors.bankCbe;
                        brandIcon = Icons.account_balance_rounded;
                      } else if (provider.contains('BOA') || provider.contains('ABYSSINIA')) {
                        brandColor = AppColors.bankAbyssinia;
                        brandIcon = Icons.account_balance_wallet_rounded;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AccountTile(
                          provider: name,
                          mask: mask,
                          balance: balanceStr,
                          color: brandColor,
                          icon: brandIcon,
                        ),
                      );
                    }).toList(),
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(color: AppColors.primaryLight),
                  ),
                ),
                error: (e, _) => Text('Error loading accounts: $e',
                    style: const TextStyle(color: AppColors.expense)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final String provider;
  final String mask;
  final String balance;
  final Color color;
  final IconData icon;

  const _AccountTile({
    required this.provider,
    required this.mask,
    required this.balance,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(provider, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                Text('•••• $mask', style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(
            balance,
            style: AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
