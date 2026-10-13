import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/security/auth_state.dart';
import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/backup/backup_export_service.dart';
import '../../core/widgets/sheets/export_statement_sheet.dart';
import '../../core/widgets/sheets/server_config_sheet.dart';
import '../../data/sync/sync_provider.dart';

import '../../data/remote/api_client_provider.dart';
import '../../core/notifications/local_notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _biometricEnabled = true;
  bool _simulateOffline = false;
  bool _notificationsEnabled = true;
  bool _showAmountsOnLock = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    try {
      final client = ref.read(apiClientProvider);
      final prefs = await client.getNotificationPreferences();
      if (mounted) {
        setState(() {
          _notificationsEnabled = prefs['enabled'] == true;
          _showAmountsOnLock = prefs['show_amounts'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _syncNotificationPrefs({bool? enabled, bool? showAmounts}) async {
    try {
      final notifService = ref.read(localNotificationServiceProvider);
      if (showAmounts != null) {
        notifService.showAmountsOnLockScreen = showAmounts;
      }
      final client = ref.read(apiClientProvider);
      await client.updateNotificationPreferences(
        enabled: enabled ?? _notificationsEnabled,
        showAmounts: showAmounts ?? _showAmountsOnLock,
      );
    } catch (_) {}
  }

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
                    activeThumbColor: AppColors.accent,
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
                    activeThumbColor: AppColors.accent,
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: const BorderSide(color: AppColors.line),
                            backgroundColor: AppColors.surface2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.file_download_outlined, size: 16),
                          label: const Text('Export Statement', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          onPressed: () => ExportStatementSheet.show(
                            context,
                            onGenerate: (period, format) async {
                              final exportService = await ref.read(backupExportServiceProvider.future);
                              await exportService.exportTransactionsCsv(period: period, format: format);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.income,
                            side: const BorderSide(color: AppColors.line),
                            backgroundColor: AppColors.surface2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.shield_outlined, size: 16),
                          label: const Text('Backup Vault', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          onPressed: () => _showCreateBackupDialog(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 3. Notifications & Cloud Alerts
            const Text(
              'NOTIFICATIONS & CLOUD ALERTS',
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
                    activeThumbColor: AppColors.accent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    title: const Text('Instant Spending Alerts', style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('On-device instant alerts when approaching 80% & 100% budget', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                    value: _notificationsEnabled,
                    onChanged: (val) {
                      setState(() => _notificationsEnabled = val);
                      _syncNotificationPrefs(enabled: val);
                    },
                  ),
                  const Divider(color: AppColors.line, height: 1),
                  SwitchListTile(
                    activeThumbColor: AppColors.accent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    title: const Text('Show Amounts in Notifications', style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Display exact ETB balances in push banners', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                    value: _showAmountsOnLock,
                    onChanged: (val) {
                      setState(() => _showAmountsOnLock = val);
                      _syncNotificationPrefs(showAmounts: val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 4. Sync & Cloud Gateway
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
                    activeThumbColor: AppColors.amber,
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
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: const Icon(Icons.dns_rounded, color: AppColors.accent, size: 20),
                    title: const Text('Backend Server Endpoint', style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      ref.watch(serverConfigProvider),
                      style: const TextStyle(color: AppColors.text3, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.text3, size: 12),
                    onTap: () => ServerConfigSheet.show(context),
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
                  side: BorderSide(color: AppColors.expense.withValues(alpha: 0.4)),
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

  void _showCreateBackupDialog() {
    final passwordCtrl = TextEditingController();
    bool isObscured = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.shield_rounded, color: AppColors.income, size: 22),
              SizedBox(width: 8),
              Text('Encrypted Backup', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter a password to encrypt your complete financial ledger with AES-256-GCM. You will need this password to restore your vault.',
                style: TextStyle(color: AppColors.text2, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordCtrl,
                obscureText: isObscured,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  hintText: 'Vault Password (min 6 chars)',
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: Icon(isObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.text3, size: 18),
                    onPressed: () => setDialogState(() => isObscured = !isObscured),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.text3)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.income,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final pw = passwordCtrl.text.trim();
                if (pw.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password must be at least 6 characters')),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                try {
                  final exportService = await ref.read(backupExportServiceProvider.future);
                  await exportService.createEncryptedBackupFile(password: pw);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to create backup: $e')),
                    );
                  }
                }
              },
              child: const Text('Create & Share', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
