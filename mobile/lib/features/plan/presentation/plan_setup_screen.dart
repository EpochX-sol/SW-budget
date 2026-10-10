import 'package:flutter/material.dart';
import '../../../domain/use_cases/adaptive_spending_engine.dart';
import '../models/spending_plan_models.dart';

class PlanSetupScreen extends StatefulWidget {
  const PlanSetupScreen({super.key});

  @override
  State<PlanSetupScreen> createState() => _PlanSetupScreenState();
}

class _PlanSetupScreenState extends State<PlanSetupScreen> {
  final _nameController = TextEditingController(text: 'My Spending Plan');
  final _budgetController = TextEditingController(text: '14000');
  final _savingGoalController = TextEditingController(text: '1000');

  int _selectedPresetDays = 14; // 2 weeks default
  double _reservePercent = 5.0;
  RolloverMode _rolloverMode = RolloverMode.spreadEvenly;

  final List<FixedExpense> _fixedExpenses = [
    const FixedExpense(id: 'fe_1', planId: '', title: 'Apartment Rent / Wifi', amount: 1500),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    _savingGoalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final budget = double.tryParse(_budgetController.text) ?? 10000.0;
    final fixedTotal = _fixedExpenses.fold(0.0, (sum, f) => sum + f.amount);
    final reserve = budget * (_reservePercent / 100);
    final savings = double.tryParse(_savingGoalController.text) ?? 0.0;
    final flexiblePool = (budget - fixedTotal - reserve - savings).clamp(0.0, double.infinity);
    final dailyAllowance = _selectedPresetDays > 0 ? flexiblePool / _selectedPresetDays : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Setup Spending Plan'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          // Period Presets
          const Text('PLAN DURATION', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildPresetChip('1 Week', 7),
              const SizedBox(width: 8),
              _buildPresetChip('2 Weeks', 14),
              const SizedBox(width: 8),
              _buildPresetChip('1 Month', 30),
            ],
          ),
          const SizedBox(height: 20),

          // Total Budget Input
          TextField(
            controller: _budgetController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              labelText: 'Total Budget (ETB)',
              labelStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Savings Goal
          TextField(
            controller: _savingGoalController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              labelText: 'Target Savings (ETB)',
              labelStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),

          // Emergency Reserve Slider
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Emergency Reserve', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                      Text('${_reservePercent.toStringAsFixed(0)}% (${reserve.toStringAsFixed(0)} ETB)', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: _reservePercent,
                    min: 0,
                    max: 20,
                    divisions: 20,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => setState(() => _reservePercent = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Live Preview Card
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF10B981), width: 1)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PREVIEW OF ALLOWANCE', style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    '${dailyAllowance.toStringAsFixed(2)} ETB / day',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Flexible pool: ${flexiblePool.toStringAsFixed(0)} ETB over $_selectedPresetDays days',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save and Activate Plan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, int days) {
    final selected = _selectedPresetDays == days;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFF10B981),
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold),
      backgroundColor: const Color(0xFF1E293B),
      onSelected: (_) => setState(() => _selectedPresetDays = days),
    );
  }
}
