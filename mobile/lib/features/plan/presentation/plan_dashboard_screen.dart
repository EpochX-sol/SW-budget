import 'package:flutter/material.dart';
import '../../../domain/use_cases/adaptive_spending_engine.dart';
import '../models/spending_plan_models.dart';
import 'plan_setup_screen.dart';
import 'plan_simulator_screen.dart';

class PlanDashboardScreen extends StatefulWidget {
  final BudgetPlan? initialPlan;
  final PlanSnapshot? initialSnapshot;

  const PlanDashboardScreen({
    super.key,
    this.initialPlan,
    this.initialSnapshot,
  });

  @override
  State<PlanDashboardScreen> createState() => _PlanDashboardScreenState();
}

class _PlanDashboardScreenState extends State<PlanDashboardScreen> {
  late BudgetPlan? _plan;
  late PlanSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _plan = widget.initialPlan;
    _snapshot = widget.initialSnapshot;

    // If no plan is passed, create a default demonstrative 2-week active plan
    if (_plan == null && _snapshot == null) {
      final now = DateTime.now();
      _plan = BudgetPlan(
        id: 'default_plan',
        userId: 'user_1',
        name: 'October 2-Week Plan',
        totalAmount: 14000.0,
        startDate: now.subtract(const Duration(days: 3)),
        endDate: now.add(const Duration(days: 10)),
        rolloverMode: RolloverMode.spreadEvenly,
        reservePercent: 5.0,
        savingGoal: 1000.0,
        fixedExpenses: [
          FixedExpense(
            id: 'fe_1',
            planId: 'default_plan',
            title: 'Apartment Wifi',
            amount: 1500.0,
            dueDate: now,
            paid: true,
          ),
        ],
      );

      _snapshot = AdaptiveSpendingEngine.computeSnapshot(
        planId: _plan!.id,
        asOfDate: AdaptiveSpendingEngine.toAddisAbabaDateString(now),
        budget: _plan!.totalAmount,
        fixedTotal: _plan!.fixedExpensesTotal,
        reservePercent: _plan!.reservePercent,
        savingGoal: _plan!.savingGoal,
        totalDays: _plan!.totalDays,
        dayIndex: 4,
        spentByDay: [650.0, 720.0, 580.0, 450.0],
        rolloverMode: _plan!.rolloverMode,
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'RED':
        return Colors.redAccent;
      case 'ORANGE':
        return Colors.orangeAccent;
      case 'YELLOW':
        return Colors.amber;
      case 'GREEN':
      default:
        return const Color(0xFF10B981);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_plan == null || _snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Adaptive Spending Plan')),
        body: Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create Spending Plan'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlanSetupScreen()),
              );
            },
          ),
        ),
      );
    }

    final snap = _snapshot!;
    final statusColor = _getStatusColor(snap.status);
    final allowance = snap.today['allowance'] as double? ?? 0.0;
    final spentToday = snap.today['spent'] as double? ?? 0.0;
    final remainingToday = snap.today['remainingToday'] as double? ?? 0.0;
    final variancePct = snap.today['varianceVsAllowancePct'] as double?;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(_plan!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_graph_outlined),
            tooltip: 'Spending Simulator',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlanSimulatorScreen(
                    flexibleBudget: snap.totals['flexible'] ?? 10000.0,
                    totalDays: snap.days['total'] ?? 14,
                    currentDay: snap.days['elapsed'] ?? 4,
                    spentTotal: snap.totals['spent'] ?? 2400.0,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Setup Plan',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlanSetupScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 1. Today Allowance Hero Card
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: statusColor.withOpacity(0.4), width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TODAY ALLOWANCE',
                        style: TextStyle(color: Colors.white70, letterSpacing: 1.2, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          snap.status,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${allowance.toStringAsFixed(2)} ETB',
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Spent Today', style: TextStyle(color: Colors.white60, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('${spentToday.toStringAsFixed(2)} ETB', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Remaining Today', style: TextStyle(color: Colors.white60, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('${remainingToday.toStringAsFixed(2)} ETB', style: TextStyle(color: remainingToday >= 0 ? const Color(0xFF10B981) : Colors.redAccent, fontSize: 15, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  if (variancePct != null) ...[
                    const Divider(color: Colors.white12, height: 24),
                    Text(
                      variancePct <= 0
                          ? '✓ You are ${variancePct.abs().toStringAsFixed(1)}% under today\'s plan. Stay on track!'
                          : '⚠️ You are ${variancePct.toStringAsFixed(1)}% over today\'s plan.',
                      style: TextStyle(color: variancePct <= 0 ? const Color(0xFF10B981) : Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. Tomorrow Adjusted Target Card
          if (snap.tomorrow != null)
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.wb_sunny_outlined, color: Colors.indigoAccent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('TOMORROW FORECAST', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                          const SizedBox(height: 4),
                          Text(
                            'Spend up to ${(snap.tomorrow!['allowance'] as double).toStringAsFixed(2)} ETB',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${(snap.tomorrow!['pctOfBase'] as double).toStringAsFixed(0)}% of your original daily limit',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),

          // 3. Weekly Breakdown Card
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CALENDAR WEEKS', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ...snap.weeks.map((week) {
                    final progress = (week.spent / (week.baseTarget > 0 ? week.baseTarget : 1.0)).clamp(0.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Week ${week.index}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              Text('${week.spent.toStringAsFixed(0)} / ${week.baseTarget.toStringAsFixed(0)} ETB', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(progress > 0.9 ? Colors.orangeAccent : const Color(0xFF10B981)),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 4. Period & Pace Overview
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PERIOD OVERVIEW', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniStat('Total Budget', '${(snap.totals['budget'] ?? 0).toStringAsFixed(0)} ETB'),
                      _buildMiniStat('Days Left', '${snap.days['left'] ?? 0} days'),
                      _buildMiniStat('Remaining', '${(snap.totals['remaining'] ?? 0).toStringAsFixed(0)} ETB'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
