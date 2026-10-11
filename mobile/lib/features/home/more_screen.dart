import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/backup/backup_export_service.dart';
import '../../core/security/auth_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sheets/export_statement_sheet.dart';
import '../activity/activity_providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final reviewCountAsync = ref.watch(reviewInboxCountProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);

    final user = authState.userProfile;
    final displayName = user?['display_name'] as String? ?? 'Samuel';
    final email = user?['email'] as String? ?? 'samuel@swbudget.local';

    final reviewCount = reviewCountAsync.value ?? 0;
    final accountsCount = accountsAsync.value?.length ?? 3;

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
            const SizedBox(height: 18),

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
          color: iconColor.withOpacity(0.12),
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
                color: (badgeColor ?? AppColors.accent).withOpacity(0.15),
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
}
