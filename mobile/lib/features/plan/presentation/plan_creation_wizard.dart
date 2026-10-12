import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database_provider.dart';
import '../plan_providers.dart';

class PlanCreationWizard extends ConsumerStatefulWidget {
  const PlanCreationWizard({super.key});

  @override
  ConsumerState<PlanCreationWizard> createState() => _PlanCreationWizardState();
}

class _PlanCreationWizardState extends ConsumerState<PlanCreationWizard> {
  int _currentStep = 0;

  // Step 1: Period
  String _periodType = 'monthly'; // daily, weekly, monthly, yearly, custom
  int _weeklyStartDay = 1; // 1 = Monday
  int _monthlyStartDay = 1; // 1 to 28
  DateTime _customStartDate = DateTime.now();
  DateTime _customEndDate = DateTime.now().add(const Duration(days: 29));

  // Step 2: Banks
  bool _allBanks = true;
  final Set<String> _selectedBankIds = {};

  // Step 3: Money
  final _limitController = TextEditingController(text: '8000');
  String _reserveType = 'none'; // none, fixed, percentage
  final _reserveValueController = TextEditingController(text: '0');

  // Step 4: Expected Expenses & Rules
  final List<Map<String, dynamic>> _expectedExpenses = [];
  bool _countFees = true;
  bool _countWithdrawals = true;
  String _reactionMode = 'adaptive'; // adaptive, fixed
  bool _morningBrief = true;
  String _morningBriefTime = '07:30';
  bool _dailyReport = true;
  String _dailyReportTime = '21:00';

  @override
  void dispose() {
    _limitController.dispose();
    _reserveValueController.dispose();
    super.dispose();
  }

  DateTime _calculateStartDate() {
    final now = DateTime.now();
    switch (_periodType) {
      case 'daily':
        return DateTime(now.year, now.month, now.day);
      case 'weekly':
        final curWeekday = now.weekday; // 1=Mon .. 7=Sun
        final diff = (curWeekday - _weeklyStartDay) % 7;
        return DateTime(now.year, now.month, now.day).subtract(Duration(days: diff));
      case 'monthly':
        final day = _monthlyStartDay.clamp(1, 28);
        if (now.day >= day) {
          return DateTime(now.year, now.month, day);
        } else {
          return DateTime(now.year, now.month - 1, day);
        }
      case 'yearly':
        return DateTime(now.year, 1, 1);
      case 'custom':
      default:
        return _customStartDate;
    }
  }

  DateTime _calculateEndDate(DateTime start) {
    switch (_periodType) {
      case 'daily':
        return DateTime(start.year, start.month, start.day, 23, 59, 59);
      case 'weekly':
        return start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      case 'monthly':
        final nextMonth = DateTime(start.year, start.month + 1, start.day);
        return nextMonth.subtract(const Duration(seconds: 1));
      case 'yearly':
        return DateTime(start.year, 12, 31, 23, 59, 59);
      case 'custom':
      default:
        return _customEndDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final startDate = _calculateStartDate();
    final endDate = _calculateEndDate(startDate);
    final totalDays = endDate.difference(startDate).inDays + 1;
    final limit = double.tryParse(_limitController.text) ?? 8000.0;
    final reserveVal = double.tryParse(_reserveValueController.text) ?? 0.0;
    double reserve = 0.0;
    if (_reserveType == 'fixed') {
      reserve = reserveVal.clamp(0.0, limit);
    } else if (_reserveType == 'percentage') {
      reserve = limit * (reserveVal.clamp(0.0, 90.0) / 100.0);
    }
    final spendable = (limit - reserve).clamp(0.0, double.infinity);
    final dailyBaseline = totalDays > 0 ? spendable / totalDays : spendable;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          _currentStep == 4 ? 'Review Plan' : 'Step ${_currentStep + 1} of 4',
          style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Step Progress Bar
          LinearProgressIndicator(
            value: (_currentStep + 1) / 5.0,
            backgroundColor: AppColors.surface2,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            minHeight: 3,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_currentStep == 0) _buildStepPeriod(startDate, endDate, totalDays),
                if (_currentStep == 1) _buildStepBanks(),
                if (_currentStep == 2) _buildStepMoney(totalDays, spendable, dailyBaseline),
                if (_currentStep == 3) _buildStepExpectedExpenses(),
                if (_currentStep == 4) _buildStepReview(startDate, endDate, totalDays, limit, spendable, reserve, dailyBaseline),
              ],
            ),
          ),
          // Bottom Navigation Buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.surface2)),
            ),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.surface3),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => setState(() => _currentStep--),
                      child: const Text('Back', style: TextStyle(color: AppColors.text)),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      if (_currentStep < 4) {
                        setState(() => _currentStep++);
                      } else {
                        _saveAndCreatePlan(startDate, endDate);
                      }
                    },
                    child: Text(
                      _currentStep == 4 ? 'Create Plan' : 'Continue',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 1: PERIOD ---
  Widget _buildStepPeriod(DateTime start, DateTime end, int days) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose Plan Period', style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('How long do you intend to budget for? There is no auto-renew; the plan finishes on its last day.', style: TextStyle(color: AppColors.text3, fontSize: 13)),
        const SizedBox(height: 20),
        _buildPeriodTile('monthly', 'Monthly', 'Matches your monthly salary or calendar month (Default: 1st)'),
        _buildPeriodTile('weekly', 'Weekly', '7 days; starts on Monday'),
        _buildPeriodTile('daily', 'Daily', 'A single 24-hour spending target'),
        _buildPeriodTile('yearly', 'Yearly', 'One calendar year target'),
        _buildPeriodTile('custom', 'Custom Range', 'Pick exact start and end dates (up to 366 days)'),
        const SizedBox(height: 16),
        if (_periodType == 'monthly') ...[
          const Text('MONTHLY START DAY (PAYDAY)', style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _monthlyStartDay,
            dropdownColor: AppColors.surface,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            items: List.generate(28, (i) => i + 1).map((d) {
              return DropdownMenuItem<int>(
                value: d,
                child: Text('Day $d of every month (e.g. ${d == 25 ? 'Payday' : d == 1 ? '1st' : '$d'})', style: const TextStyle(color: AppColors.text)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _monthlyStartDay = val);
            },
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, color: AppColors.accent, size: 18),
              const SizedBox(width: 10),
              Text(
                '${DateFormat('d MMM yyyy').format(start)} – ${DateFormat('d MMM yyyy').format(end)} ($days days)',
                style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodTile(String value, String title, String subtitle) {
    final selected = _periodType == value;
    return GestureDetector(
      onTap: () => setState(() => _periodType = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.accent : AppColors.surface2, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.accent : AppColors.text3, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: AppColors.text, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.text3, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- STEP 2: BANKS ---
  Widget _buildStepBanks() {
    final dbAsync = ref.watch(databaseProvider);
    return dbAsync.when(
      data: (db) {
        final accounts = db.getAccounts();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Which banks should this plan watch?', style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Only transactions from watched accounts will count toward your plan.', style: TextStyle(color: AppColors.text3, fontSize: 13)),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All banks (Default)', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
              subtitle: const Text('Every account you have now and any you add later', style: TextStyle(color: AppColors.text3, fontSize: 12)),
              value: _allBanks,
              activeColor: AppColors.accent,
              onChanged: (val) {
                setState(() {
                  _allBanks = val;
                  if (val) _selectedBankIds.clear();
                });
              },
            ),
            const Divider(color: AppColors.surface2, height: 24),
            if (!_allBanks) ...[
              const Text('SELECT ACCOUNTS', style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...accounts.map((acc) {
                final id = acc['id'] as String;
                final name = acc['name'] as String;
                final provider = acc['provider'] as String;
                final checked = _selectedBankIds.contains(id);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                  subtitle: Text(provider.toUpperCase(), style: const TextStyle(color: AppColors.text3, fontSize: 12)),
                  value: checked,
                  activeColor: AppColors.accent,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedBankIds.add(id);
                      } else {
                        _selectedBankIds.remove(id);
                      }
                    });
                  },
                );
              }),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Text('Failed to load accounts'),
    );
  }

  // --- STEP 3: MONEY ---
  Widget _buildStepMoney(int days, double spendable, double daily) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Spending Limit & Reserve', style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Set how much you plan to spend on everyday items. Expected big expenses (rent, bills) are added separately in the next step.', style: TextStyle(color: AppColors.text3, fontSize: 13)),
        const SizedBox(height: 20),
        const Text('EVERYDAY SPENDING LIMIT (ETB)', style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _limitController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            prefixText: 'ETB ',
            prefixStyle: const TextStyle(color: AppColors.accent, fontSize: 22, fontWeight: FontWeight.w800),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        const Text('EMERGENCY RESERVE (INSIDE LIMIT)', style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildReserveChip('none', 'None (Default)'),
            const SizedBox(width: 8),
            _buildReserveChip('percentage', 'Percentage'),
            const SizedBox(width: 8),
            _buildReserveChip('fixed', 'Fixed ETB'),
          ],
        ),
        if (_reserveType != 'none') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _reserveValueController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: _reserveType == 'percentage' ? 'e.g. 10%' : 'e.g. 500 ETB',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SUMMARY LINE', style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(
                'You can spend ETB ${NumberFormat('#,##0').format(spendable)} over $days days, about ETB ${NumberFormat('#,##0').format(daily)} per day.',
                style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReserveChip(String type, String label) {
    final selected = _reserveType == type;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: selected ? AppColors.background : AppColors.text, fontWeight: FontWeight.w600, fontSize: 12)),
      selected: selected,
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surface,
      onSelected: (_) => setState(() => _reserveType = type),
    );
  }

  // --- STEP 4: EXPECTED EXPENSES & RULES ---
  Widget _buildStepExpectedExpenses() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Expected Expenses & Rules', style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Expected expenses (rent, school fee) sit OUTSIDE your spending limit. They are listed in your plan but not counted in plan spent.', style: TextStyle(color: AppColors.text3, fontSize: 13)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('EXPECTED EXPENSES (${_expectedExpenses.length})', style: const TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700)),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: AppColors.accent),
              label: const Text('Add', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
              onPressed: _showAddExpectedExpenseDialog,
            ),
          ],
        ),
        if (_expectedExpenses.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
            child: const Center(
              child: Text('No expected expenses added yet. Tap Add to list known commitments.', style: TextStyle(color: AppColors.text3, fontSize: 12)),
            ),
          )
        else
          ..._expectedExpenses.map((exp) {
            final name = exp['name'] as String;
            final amount = (exp['amount'] as num).toDouble();
            final due = exp['due_date'] as String?;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                        if (due != null) Text('Due: $due', style: const TextStyle(color: AppColors.text3, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text('ETB ${NumberFormat('#,##0').format(amount)}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.negative),
                    onPressed: () => setState(() => _expectedExpenses.remove(exp)),
                  ),
                ],
              ),
            );
          }),
        const Divider(color: AppColors.surface2, height: 28),
        const Text('RULES & COUNTING', style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Count fees & service charges', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
          subtitle: const Text('Service charges and bank VAT count as spending (Default: on)', style: TextStyle(color: AppColors.text3, fontSize: 12)),
          value: _countFees,
          activeColor: AppColors.accent,
          onChanged: (v) => setState(() => _countFees = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Count cash withdrawals', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
          subtitle: const Text('Cash withdrawals count as spending (Default: on)', style: TextStyle(color: AppColors.text3, fontSize: 12)),
          value: _countWithdrawals,
          activeColor: AppColors.accent,
          onChanged: (v) => setState(() => _countWithdrawals = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Adaptive daily allowance', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
          subtitle: const Text('Spreads overspend/underspend over remaining days (Default: adaptive)', style: TextStyle(color: AppColors.text3, fontSize: 12)),
          value: _reactionMode == 'adaptive',
          activeColor: AppColors.accent,
          onChanged: (v) => setState(() => _reactionMode = v ? 'adaptive' : 'fixed'),
        ),
      ],
    );
  }

  void _showAddExpectedExpenseDialog() {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    DateTime? pickedDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Expected Expense', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  hintText: 'Expense name (e.g. House rent, School fees)',
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  hintText: 'Amount (ETB)',
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  if (name.isNotEmpty && amt > 0) {
                    setState(() {
                      _expectedExpenses.add({
                        'name': name,
                        'amount': amt,
                        'due_date': pickedDate != null ? DateFormat('yyyy-MM-dd').format(pickedDate!) : null,
                        'status': 'expected',
                      });
                    });
                    Navigator.of(ctx).pop();
                  }
                },
                child: const Text('Add to Plan', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- STEP 5: REVIEW ---
  Widget _buildStepReview(
    DateTime start,
    DateTime end,
    int days,
    double limit,
    double spendable,
    double reserve,
    double daily,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ready to Start Your Plan', style: TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Review your settings below. When you tap Create Plan, your active dashboard will appear immediately.', style: TextStyle(color: AppColors.text3, fontSize: 13)),
        const SizedBox(height: 20),
        _buildReviewRow('Period', '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)} ($days days)'),
        _buildReviewRow('Everyday Limit', 'ETB ${NumberFormat('#,##0').format(limit)}'),
        if (reserve > 0) _buildReviewRow('Emergency Reserve', 'ETB ${NumberFormat('#,##0').format(reserve)}'),
        _buildReviewRow('Spendable Budget', 'ETB ${NumberFormat('#,##0').format(spendable)}'),
        _buildReviewRow('Normal Daily Plan', 'ETB ${NumberFormat('#,##0').format(daily)} / day'),
        _buildReviewRow('Watched Banks', _allBanks ? 'All accounts' : '${_selectedBankIds.length} accounts'),
        _buildReviewRow('Expected Expenses', '${_expectedExpenses.length} listed (separate from limit)'),
        _buildReviewRow('Reaction Mode', _reactionMode == 'adaptive' ? 'Adaptive daily rebalance' : 'Fixed allowance'),
        _buildReviewRow('Reports', 'Morning brief (07:30) & Daily report (21:00) on'),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.accent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'When the period ends, the plan shows a final summary and then deletes itself cleanly. There is no auto-renew.',
                  style: TextStyle(color: AppColors.text2, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: AppColors.text3, fontSize: 13)),
          Text(value, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _saveAndCreatePlan(DateTime start, DateTime end) async {
    final limit = double.tryParse(_limitController.text) ?? 8000.0;
    final reserveVal = double.tryParse(_reserveValueController.text) ?? 0.0;

    await ref.read(planControllerProvider).createPlan(
      name: '${DateFormat('MMMM').format(start)} Spending Plan',
      periodType: _periodType,
      startDate: start,
      endDate: end,
      monthlyStartDay: _monthlyStartDay,
      spendingLimit: limit,
      reserveType: _reserveType,
      reserveValue: reserveVal,
      watchedBankIds: _allBanks ? null : _selectedBankIds.toList(),
      countFees: _countFees,
      countWithdrawals: _countWithdrawals,
      reactionMode: _reactionMode,
      morningBriefEnabled: _morningBrief,
      morningBriefTime: _morningBriefTime,
      dailyReportEnabled: _dailyReport,
      dailyReportTime: _dailyReportTime,
      expectedExpenses: _expectedExpenses,
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
