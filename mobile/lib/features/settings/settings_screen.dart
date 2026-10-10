import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/security/auth_state.dart';
import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sheets/export_statement_sheet.dart';
import '../../data/sync/sync_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _biometricEnabled = true;
  bool _simulateOffline = false;
  bool _simulateFailedSync = false;

  @override
  Widget build(BuildContext context) {
    final isPrivate = ref.watch(privacyModeProvider);
    final syncState = ref.watch(syncStateProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.text, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Settings & Security',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // 1. Security & Privacy Card
            const Text(
              'SECURITY & PRIVACY',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    activeColor: AppColors.accent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    title: const Text(
                      'Biometric App Lock',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Require fingerprint or device PIN when opening',
                      style: TextStyle(color: AppColors.text3, fontSize: 11),
                    ),
                    value: _biometricEnabled,
                    onChanged: (val) {
                      setState(() {
                        _biometricEnabled = val;
                      });
                    },
                  ),
                  const Divider(color: AppColors.line, height: 1),
                  SwitchListTile(
                    activeColor: AppColors.accent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    title: const Text(
                      'Privacy Eye Mode',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Mask financial amounts with •••• across all screens',
                      style: TextStyle(color: AppColors.text3, fontSize: 11),
                    ),
                    value: isPrivate,
                    onChanged: (val) {
                      ref.read(privacyModeProvider.notifier).state = val;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 2. SQLCipher Vault Encryption Card
            const Text(
              'LOCAL DATABASE ENCRYPTION',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, color: AppColors.income, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'SQLCipher v4 · AES-256-GCM',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ledger, SMS records, and debts are encrypted at rest with keys protected by hardware Android Keystore. Data never touches remote servers without your explicit passkey.',
                    style: TextStyle(color: AppColors.text3, fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.line),
                        backgroundColor: AppColors.surface2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text('Export Tax Statement', style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () => ExportStatementSheet.show(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 3. Sync & Cloud Gateway
            const Text(
              'SYNC & CLOUD GATEWAY',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sync engine status', style: TextStyle(color: AppColors.text2, fontSize: 12)),
                      Text(
                        syncState.isSyncing ? 'Syncing...' : 'Online & Idle',
                        style: TextStyle(
                          color: syncState.isSyncing ? AppColors.accent : AppColors.income,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pending mutation queue', style: TextStyle(color: AppColors.text2, fontSize: 12)),
                      Text(
                        '${syncState.unsyncedCount} items',
                        style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentBg,
                        foregroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.sync_rounded, size: 16),
                      label: const Text('Trigger Manual Sync', style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () {
                        ref.read(syncStateProvider.notifier).triggerSync();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Syncing with private encrypted backend...')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 4. Diagnostics & Developer Sandbox
            const Text(
              'DIAGNOSTICS & TESTING SANDBOX',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    activeColor: AppColors.amber,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    title: const Text('Simulate Offline Mode', style: TextStyle(color: AppColors.text, fontSize: 13)),
                    value: _simulateOffline,
                    onChanged: (val) {
                      setState(() {
                        _simulateOffline = val;
                      });
                    },
                  ),
                  const Divider(color: AppColors.line, height: 1),
                  SwitchListTile(
                    activeColor: AppColors.expense,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    title: const Text('Simulate Sync Network Error', style: TextStyle(color: AppColors.text, fontSize: 13)),
                    value: _simulateFailedSync,
                    onChanged: (val) {
                      setState(() {
                        _simulateFailedSync = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Sign Out Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.expense,
                  side: BorderSide(color: AppColors.expense.withOpacity(0.4)),
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Lock App & Log Out', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () {
                  ref.read(authStateProvider.notifier).logout();
                  context.go('/welcome');
                },
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
