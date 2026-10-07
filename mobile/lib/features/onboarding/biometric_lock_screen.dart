import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/security/auth_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

class BiometricLockScreen extends ConsumerStatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  ConsumerState<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends ConsumerState<BiometricLockScreen> {
  bool _isAuthenticating = false;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    // Auto-trigger prompt on screen display
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptBiometrics();
    });
  }

  Future<void> _promptBiometrics() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _statusText = 'Touch fingerprint sensor or scan face...';
    });

    final success = await ref.read(authStateProvider.notifier).unlockWithBiometrics();

    if (mounted) {
      setState(() {
        _isAuthenticating = false;
        if (success) {
          _statusText = 'Unlocked';
          context.go('/home');
        } else {
          _statusText = 'Authentication failed. Tap icon to retry.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final displayName = authState.userProfile?['display_name'] as String? ?? 'User';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Lock Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 2),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: AppColors.primaryLight,
                  size: 36,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'SW-budget Locked',
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Welcome back, $displayName',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              const Spacer(flex: 2),

              // Biometric Touch Trigger
              GestureDetector(
                onTap: _promptBiometrics,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryLight, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryLight.withOpacity(0.25),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    color: AppColors.primaryLight,
                    size: 52,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _statusText ?? 'Tap to unlock with Biometrics',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),

              const Spacer(flex: 3),

              // Sign Out option
              TextButton(
                onPressed: () async {
                  await ref.read(authStateProvider.notifier).logout();
                  if (context.mounted) {
                    context.go('/welcome');
                  }
                },
                child: Text(
                  'Switch Account or Sign Out',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
