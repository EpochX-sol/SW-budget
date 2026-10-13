import 'package:flutter/material.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/notifications/notification_settings_service.dart';
import '../../core/notifications/notification_scheduler.dart';
import '../../core/theme/app_colors.dart';
import 'notification_history_screen.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _loading = true;
  bool _hasPermission = true;

  bool _transactionEnabled = true;
  bool _failedParseReviewEnabled = true;
  bool _budgetEnabled = true;
  bool _dailyEnabled = true;
  bool _weeklyEnabled = true;
  bool _monthlyEnabled = false;
  TimeOfDay _dailyTime = const TimeOfDay(hour: 20, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = NotificationSettingsService.instance;
    final hasPerm = await NotificationService.instance.arePermissionsGranted();

    final tx = await settings.isTransactionNotificationsEnabled();
    final failedParse = await settings.isFailedParseReviewNotificationsEnabled();
    final budget = await settings.isBudgetAlertsEnabled();
    final daily = await settings.isDailySummaryEnabled();
    final weekly = await settings.isWeeklySummaryEnabled();
    final monthly = await settings.isMonthlySummaryEnabled();
    final time = await settings.getDailySummaryTime();

    if (!mounted) return;
    setState(() {
      _hasPermission = hasPerm;
      _transactionEnabled = tx;
      _failedParseReviewEnabled = failedParse;
      _budgetEnabled = budget;
      _dailyEnabled = daily;
      _weeklyEnabled = weekly;
      _monthlyEnabled = monthly;
      _dailyTime = time;
      _loading = false;
    });
  }

  Future<void> _requestPermission() async {
    final granted =
        await NotificationService.instance.requestPermissionsIfNeeded();
    if (mounted) {
      setState(() => _hasPermission = granted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Notification History',
            icon: const Icon(Icons.history, color: AppColors.accent),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationHistoryScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                if (!_hasPermission) _buildPermissionBanner(),
                _buildSectionHeader('INSTANT TRANSACTION ALERTS'),
                _buildSwitchCard(
                  title: 'Transaction Notifications',
                  subtitle:
                      'Instant alert with counterparty entry & quick-categorize buttons',
                  value: _transactionEnabled,
                  onChanged: (val) async {
                    setState(() => _transactionEnabled = val);
                    await NotificationSettingsService.instance
                        .setTransactionNotificationsEnabled(val);
                  },
                ),
                _buildSwitchCard(
                  title: 'Failed Parse Reviews',
                  subtitle:
                      'Prompt with Yes / No buttons when a bank SMS cannot be parsed',
                  value: _failedParseReviewEnabled,
                  onChanged: (val) async {
                    setState(() => _failedParseReviewEnabled = val);
                    await NotificationSettingsService.instance
                        .setFailedParseReviewNotificationsEnabled(val);
                  },
                ),
                const SizedBox(height: 16),
                _buildSectionHeader('BUDGET & SPENDING ALERTS'),
                _buildSwitchCard(
                  title: 'Budget Warnings & Limits',
                  subtitle:
                      'Alert when approaching (80%) or exceeding (100%) budget envelope',
                  value: _budgetEnabled,
                  onChanged: (val) async {
                    setState(() => _budgetEnabled = val);
                    await NotificationSettingsService.instance
                        .setBudgetAlertsEnabled(val);
                  },
                ),
                const SizedBox(height: 16),
                _buildSectionHeader('PERIODIC SPENDING SUMMARIES'),
                _buildSwitchCard(
                  title: 'Daily Spending Summary',
                  subtitle:
                      'Receive daily total spending at ${_formatTimeOfDay(_dailyTime)}',
                  value: _dailyEnabled,
                  onChanged: (val) async {
                    setState(() => _dailyEnabled = val);
                    await NotificationSettingsService.instance
                        .setDailySummaryEnabled(val);
                    await NotificationScheduler.syncSpendingSummarySchedule();
                  },
                  trailing: TextButton(
                    onPressed: _selectDailyTime,
                    child: Text(
                      _formatTimeOfDay(_dailyTime),
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                _buildSwitchCard(
                  title: 'Weekly Spending Summary',
                  subtitle: 'Summary of the week delivered every Sunday evening',
                  value: _weeklyEnabled,
                  onChanged: (val) async {
                    setState(() => _weeklyEnabled = val);
                    await NotificationSettingsService.instance
                        .setWeeklySummaryEnabled(val);
                    await NotificationScheduler.syncSpendingSummarySchedule();
                  },
                ),
                _buildSwitchCard(
                  title: 'Monthly Spending Summary',
                  subtitle: 'Summary of the month delivered on the final day',
                  value: _monthlyEnabled,
                  onChanged: (val) async {
                    setState(() => _monthlyEnabled = val);
                    await NotificationSettingsService.instance
                        .setMonthlySummaryEnabled(val);
                    await NotificationScheduler.syncSpendingSummarySchedule();
                  },
                ),
                const SizedBox(height: 24),
                _buildSectionHeader('TEST NOTIFICATIONS'),
                _buildTestCard(),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Notification permission is disabled. Grant permission to receive alerts.',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: _requestPermission,
            child: const Text(
              'Enable',
              style: TextStyle(
                color: AppColors.amber,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSwitchCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
          Switch(
            value: value,
            activeThumbColor: AppColors.accent,
            activeTrackColor: AppColors.accentBg,
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.surface2,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildTestCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildTestButton(
            label: 'Test Transaction Notification',
            icon: Icons.receipt_long,
            onTap: () async {
              await NotificationService.instance.showTestTransactionNotification();
              _showSnackBar('Sent test transaction notification');
            },
          ),
          const Divider(color: AppColors.line, height: 16),
          _buildTestButton(
            label: 'Test Daily Spending Summary',
            icon: Icons.today,
            onTap: () async {
              await NotificationService.instance
                  .showDailySpendingTestNotification(amount: 450.0);
              _showSnackBar('Sent test daily summary');
            },
          ),
          const Divider(color: AppColors.line, height: 16),
          _buildTestButton(
            label: 'Test Budget Warning Alert',
            icon: Icons.pie_chart,
            onTap: () async {
              await NotificationService.instance.showBudgetAlertNotification(
                id: 9999,
                title: 'Budget Warning',
                body: 'Dining budget is 85.0% used',
              );
              _showSnackBar('Sent test budget warning');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTestButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.send_rounded, color: AppColors.textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDailyTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dailyTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dailyTime = picked);
      await NotificationSettingsService.instance.setDailySummaryTime(picked);
      await NotificationScheduler.syncSpendingSummarySchedule();
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.surface3,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
