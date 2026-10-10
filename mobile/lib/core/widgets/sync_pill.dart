import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum SyncStateEnum { synced, syncing, offline, error }

class SyncPill extends StatelessWidget {
  final bool isSyncing;
  final bool isOffline;
  final bool hasError;
  final String lastSyncText;
  final int pendingCount;
  final VoidCallback? onSyncNow;
  final dynamic state;
  final String? lastSyncedTime;
  final VoidCallback? onTap;

  const SyncPill({
    super.key,
    this.isSyncing = false,
    this.isOffline = false,
    this.hasError = false,
    this.lastSyncText = 'Synced just now',
    this.pendingCount = 0,
    this.onSyncNow,
    this.state,
    this.lastSyncedTime,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    bool syncing = isSyncing;
    bool offline = isOffline;
    bool error = hasError;
    String text = lastSyncedTime ?? lastSyncText;

    if (state != null) {
      final stateStr = state.toString().toLowerCase();
      if (stateStr.contains('syncing')) {
        syncing = true;
      } else if (stateStr.contains('offline')) {
        offline = true;
      } else if (stateStr.contains('error')) {
        error = true;
      }
    }

    Color bg = AppColors.inBg;
    Color fg = AppColors.income;
    IconData icon = Icons.cloud_done_rounded;

    if (syncing) {
      bg = AppColors.accentBg;
      fg = AppColors.accent;
      icon = Icons.sync_rounded;
      text = 'Syncing...';
    } else if (error) {
      bg = AppColors.outBg;
      fg = AppColors.expense;
      icon = Icons.sync_problem_rounded;
      text = 'Sync error';
    } else if (offline) {
      bg = AppColors.amberBg;
      fg = AppColors.amber;
      icon = Icons.cloud_off_rounded;
      text = pendingCount > 0 ? 'Offline · $pendingCount pending' : 'Offline';
    }

    final callback = onTap ?? onSyncNow;

    return GestureDetector(
      onTap: callback,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fg.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
