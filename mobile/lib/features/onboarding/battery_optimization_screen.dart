import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/device/device_health_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class BatteryOptimizationScreen extends StatefulWidget {
  const BatteryOptimizationScreen({super.key});

  @override
  State<BatteryOptimizationScreen> createState() => _BatteryOptimizationScreenState();
}

class _BatteryOptimizationScreenState extends State<BatteryOptimizationScreen> {
  final DeviceHealthService _deviceHealth = DeviceHealthService();
  DeviceBrand _brand = DeviceBrand.other;
  bool _isExempted = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final brand = await _deviceHealth.getDeviceBrand();
    final isExempted = await _deviceHealth.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() {
        _brand = brand;
        _isExempted = isExempted;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRequestExemption() async {
    await _deviceHealth.requestIgnoreBatteryOptimizations();
    // Re-check after returning from settings
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final isExempted = await _deviceHealth.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() {
        _isExempted = isExempted;
      });
      if (isExempted) {
        context.go('/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guidance = _deviceHealth.getGuidanceForBrand(_brand);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => context.go('/home'),
            child: const Text('Skip for Now', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icon & Title
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primaryLight, width: 2),
                        ),
                        child: const Icon(
                          Icons.battery_charging_full_rounded,
                          size: 44,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Ensure Background Ingestion',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ethiopian Android phones (Tecno, Infinix, Xiaomi) aggressively kill apps when the screen is locked. Grant exemption so SW-budget never misses a bank SMS.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Status Pill
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isExempted ? AppColors.incomeSurface : AppColors.warningSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isExempted ? AppColors.incomeLight : AppColors.secondary,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isExempted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                            color: _isExempted ? AppColors.incomeLight : AppColors.secondary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isExempted
                                  ? 'Battery optimizations are ignored. Background capture is active.'
                                  : 'Action required: Battery optimization is currently active on your ${_brand.name.toUpperCase()}.',
                              style: AppTypography.bodySmall.copyWith(
                                color: _isExempted ? AppColors.incomeLight : AppColors.secondaryLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Brand-Specific Instructions
                    Text(
                      'Instructions for ${guidance.brandName} (${guidance.osSkin}):',
                      style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: guidance.steps.asMap().entries.map((entry) {
                          final stepNum = entry.key + 1;
                          final stepText = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceElevated,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.primaryLight),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$stepNum',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: AppColors.primaryLight,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    stepText,
                                    style: AppTypography.bodySmall.copyWith(height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Action Button
                    FilledButton(
                      onPressed: _handleRequestExemption,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryLight,
                        foregroundColor: AppColors.textInverse,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        _isExempted ? 'Done (Proceed to Ledger)' : 'Grant Battery Exemption',
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textInverse,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('I will do this manually in Settings'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
