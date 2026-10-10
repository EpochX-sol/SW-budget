import 'package:flutter/material.dart';
import '../../../domain/use_cases/adaptive_spending_engine.dart';

class PlanSimulatorScreen extends StatefulWidget {
  final double flexibleBudget;
  final int totalDays;
  final int currentDay;
  final double spentTotal;

  const PlanSimulatorScreen({
    super.key,
    required this.flexibleBudget,
    required this.totalDays,
    required this.currentDay,
    required this.spentTotal,
  });

  @override
  State<PlanSimulatorScreen> createState() => _PlanSimulatorScreenState();
}

class _PlanSimulatorScreenState extends State<PlanSimulatorScreen> {
  late double _proposedDailySpend;

  @override
  void initState() {
    super.initState();
    final remainingDays = widget.totalDays - widget.currentDay;
    final remainingBudget = widget.flexibleBudget - widget.spentTotal;
    _proposedDailySpend = (remainingDays > 0 && remainingBudget > 0)
        ? (remainingBudget / remainingDays).roundToDouble()
        : 500.0;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'DEFICIT':
        return Colors.redAccent;
      case 'WARNING':
        return Colors.orangeAccent;
      case 'SAFE':
      default:
        return const Color(0xFF10B981);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sim = AdaptiveSpendingEngine.simulateScenario(
      flexibleBudget: widget.flexibleBudget,
      totalDays: widget.totalDays,
      currentDay: widget.currentDay,
      spentTotal: widget.spentTotal,
      proposedDailySpend: _proposedDailySpend,
    );

    final statusColor = _getStatusColor(sim.status);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Spending Simulator'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          const Text(
            'Interactive "What-If" Analysis',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Drag the slider to test how changing your daily spending affects your final budget outcome.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // Slider Card
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Text('PROPOSED DAILY SPEND', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    '${_proposedDailySpend.toStringAsFixed(0)} ETB / day',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: _proposedDailySpend.clamp(100.0, 5000.0),
                    min: 100.0,
                    max: 5000.0,
                    divisions: 49,
                    activeColor: statusColor,
                    inactiveColor: Colors.white12,
                    onChanged: (val) {
                      setState(() {
                        _proposedDailySpend = val;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Outcome Card
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
                      const Text('PROJECTED OUTCOME', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                        child: Text(sim.status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildOutcomeRow('Projected Total Spend', '${sim.projectedTotal.toStringAsFixed(0)} ETB'),
                  const SizedBox(height: 10),
                  _buildOutcomeRow(
                    sim.projectedDiff > 0 ? 'Projected Overspend' : 'Projected Savings',
                    '${sim.projectedDiff.abs().toStringAsFixed(0)} ETB',
                    valueColor: sim.projectedDiff > 0 ? Colors.redAccent : const Color(0xFF10B981),
                  ),
                  if (sim.daysUntilExhausted != null) ...[
                    const SizedBox(height: 10),
                    _buildOutcomeRow(
                      'Budget Exhaustion',
                      'Runs out in ${sim.daysUntilExhausted!.toStringAsFixed(1)} days',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14)),
        Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
