import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/backup/backup_export_service.dart';
import '../../core/security/auth_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sheets/export_statement_sheet.dart';
import '../../data/sync/sync_provider.dart';
import '../activity/activity_providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final reviewCountAsync = ref.watch(reviewInboxCountProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final syncState = ref.watch(syncStateProvider);

    final user = authState.userProfile;
    final displayName = user?['display_name'] as String? ?? (authState.status == AuthStatus.authenticated ? 'User' : 'Guest');
    final email = user?['email'] as String? ?? (authState.status == AuthStatus.authenticated ? 'Offline Ledger' : 'Not signed in');

    final reviewCount = reviewCountAsync.value ?? 0;
    final accountsCount = accountsAsync.value?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Header
            const Text(
              'More',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 14),

            // Profile Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8AA4FF), Color(0xFF6B8AFF)],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line2, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                      style: const TextStyle(
                        color: Color(0xFF080C14),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: const TextStyle(color: AppColors.text3, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.incomeBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Encrypted on-device · Active',
                            style: TextStyle(
                              color: AppColors.income,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Cloud Sync & Backend Update Card
            _buildBackendSyncCard(context, ref, syncState),
            const SizedBox(height: 14),

            // Menu Options List
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  _buildMenuItem(
                    icon: Icons.account_balance_outlined,
                    iconColor: AppColors.accent,
                    title: 'Accounts & Institutions',
                    subtitle: 'Bank accounts, mobile money, and physical cash',
                    trailingBadge: '$accountsCount active',
                    onTap: () => context.push('/accounts'),
                  ),
                  const Divider(color: AppColors.line, height: 1),
                  _buildMenuItem(
                    icon: Icons.inbox_outlined,
                    iconColor: AppColors.amber,
                    title: 'Review Inbox',
                    subtitle: 'Triage unclear SMS, balance gaps, new senders',
                    trailingBadge: reviewCount > 0 ? '$reviewCount pending' : null,
                    badgeColor: AppColors.amber,
                    onTap: () => context.push('/review-inbox'),
                  ),
                  const Divider(color: AppColors.line, height: 1),
                  _buildMenuItem(
                    icon: Icons.handshake_outlined,
                    iconColor: AppColors.income,
                    title: 'Debts & Reimbursements',
                    subtitle: 'Money owed to you, IOUs, and work refund claims',
                    onTap: () => context.push('/debts'),
                  ),
                  const Divider(color: AppColors.line, height: 1),
                  _buildMenuItem(
                    icon: Icons.auto_awesome_rounded,
                    iconColor: AppColors.accent,
                    title: 'AI Financial Coach',
                    subtitle: 'Private on-device advice calculated from your ledger',
                    onTap: () => context.push('/coach'),
                  ),
                  const Divider(color: AppColors.line, height: 1),
                  _buildMenuItem(
                    icon: Icons.file_download_outlined,
                    iconColor: AppColors.text2,
                    title: 'Export Statement',
                    subtitle: 'Generate PDF or CSV tax reports directly on device',
                    onTap: () => ExportStatementSheet.show(
                      context,
                      onGenerate: (period, format) async {
                        final exportService = await ref.read(backupExportServiceProvider.future);
                        await exportService.exportTransactionsCsv(period: period, format: format);
                      },
                    ),
                  ),
                  const Divider(color: AppColors.line, height: 1),
                  _buildMenuItem(
                    icon: Icons.shield_outlined,
                    iconColor: AppColors.text2,
                    title: 'Settings & Security',
                    subtitle: 'Biometrics, privacy mask, SQLCipher backup, sync',
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Footer note
            Center(
              child: Column(
                children: [
                  const Text(
                    'SW-Budget v2.4.0',
                    style: TextStyle(
                      color: AppColors.text3,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Zero analytics · SQLCipher AES-256 on device',
                    style: TextStyle(
                      color: AppColors.text3,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? trailingBadge,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailingBadge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: (badgeColor ?? AppColors.accent).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                trailingBadge,
                style: TextStyle(
                  color: badgeColor ?? AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.text3, fontSize: 11),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.text3, size: 13),
      onTap: onTap,
    );
  }

  Widget _buildBackendSyncCard(
    BuildContext context,
    WidgetRef ref,
    SyncState syncState,
  ) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (syncState.isSyncing) {
      statusColor = AppColors.accent;
      statusLabel = 'Syncing...';
      statusIcon = Icons.sync_rounded;
    } else if (syncState.hasError) {
      statusColor = AppColors.expense;
      statusLabel = 'Sync Alert';
      statusIcon = Icons.error_outline_rounded;
    } else if (syncState.lastSyncTime != null) {
      statusColor = AppColors.income;
      statusLabel = 'Cloud Synced';
      statusIcon = Icons.cloud_done_outlined;
    } else {
      statusColor = AppColors.text3;
      statusLabel = 'Ready to sync';
      statusIcon = Icons.cloud_upload_outlined;
    }

    final formattedSyncTime = syncState.lastSyncTime != null
        ? 'Last synced: ${DateFormat('MMM d, h:mm a').format(syncState.lastSyncTime!)}'
        : 'Backend database has not been updated yet';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: syncState.isSyncing
              ? AppColors.accent.withValues(alpha: 0.4)
              : AppColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  statusIcon,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cloud Sync & Backend Ledger',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formattedSyncTime,
                      style: const TextStyle(
                        color: AppColors.text3,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (syncState.hasError && syncState.errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.expenseBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                syncState.errorMessage!,
                style: const TextStyle(
                  color: AppColors.expense,
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface2,
                foregroundColor: AppColors.text,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.line2),
                ),
              ),
              onPressed: syncState.isSyncing
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final result = await ref
                          .read(syncStateProvider.notifier)
                          .triggerSync();

                      if (!context.mounted) return;

                      messenger.clearSnackBars();
                      if (result.isSuccess) {
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF13221C),
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    color: AppColors.income, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    result.pushedCount > 0
                                        ? 'Backend updated: ${result.pushedCount} items safely pushed to cloud database.'
                                        : 'Backend is up to date (0 new items needed).',
                                    style: const TextStyle(
                                      color: AppColors.text,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                  color: AppColors.income.withValues(alpha: 0.3)),
                            ),
                          ),
                        );
                      } else {
                        messenger.showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF281316),
                            content: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AppColors.expense, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Update failed: ${result.errorMessage ?? "Network error"}',
                                    style: const TextStyle(
                                      color: AppColors.text,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                  color: AppColors.expense.withValues(alpha: 0.3)),
                            ),
                          ),
                        );
                      }
                    },
              icon: syncState.isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_rounded,
                      color: AppColors.accent, size: 18),
              label: Text(
                syncState.isSyncing
                    ? 'Updating Backend...'
                    : 'Update Backend',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

