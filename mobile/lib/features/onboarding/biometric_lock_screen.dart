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

class _BiometricLockScreenState extends ConsumerState<BiometricLockScreen>
    with SingleTickerProviderStateMixin {
  bool _isAuthenticating = false;
  String? _statusText;
  bool _hasError = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-trigger prompt on initial screen display
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptBiometrics();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _promptBiometrics() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _hasError = false;
      _statusText = 'Touch sensor or scan face...';
    });

    final success =
        await ref.read(authStateProvider.notifier).unlockWithBiometrics();

    if (mounted) {
      setState(() {
        _isAuthenticating = false;
        if (success) {
          _statusText = 'Unlocked';
          _hasError = false;
          context.go('/home');
        } else {
          _hasError = true;
          _statusText = 'Authentication cancelled or failed. Tap below to retry.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final displayName =
        authState.userProfile?['display_name'] as String? ?? 'User';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient centered radial glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.85,
                  colors: [
                    AppColors.accent.withOpacity(0.09),
                    AppColors.background,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SizedBox.expand(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
                child: Column(
                  children: [
                    // Top App Identity / Security Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.line2),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.shield_rounded,
                                color: AppColors.accent,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'HuluBirr Security',
                                style: TextStyle(
                                  color: AppColors.text2,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Centered Hero Content (100% centered horizontally & vertically)
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Pulsating Biometric Scanner Trigger
                              GestureDetector(
                                onTap: _promptBiometrics,
                                child: AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: _isAuthenticating
                                          ? _pulseAnimation.value
                                          : 1.0,
                                      child: child,
                                    );
                                  },
                                  child: Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          _hasError
                                              ? AppColors.expense.withOpacity(0.25)
                                              : AppColors.accent.withOpacity(0.20),
                                          _hasError
                                              ? AppColors.expense.withOpacity(0.05)
                                              : AppColors.surface2,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      border: Border.all(
                                        color: _hasError
                                            ? AppColors.expense.withOpacity(0.6)
                                            : AppColors.accent.withOpacity(0.5),
                                        width: 2.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_hasError
                                                  ? AppColors.expense
                                                  : AppColors.accent)
                                              .withOpacity(0.3),
                                          blurRadius: 36,
                                          spreadRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 88,
                                        height: 88,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.surface,
                                          border: Border.all(
                                            color: AppColors.line2,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Icon(
                                          _hasError
                                              ? Icons.lock_outline_rounded
                                              : Icons.fingerprint_rounded,
                                          color: _hasError
                                              ? AppColors.expense
                                              : AppColors.accent,
                                          size: 52,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Screen Title
                              Text(
                                'Unlock HuluBirr',
                                textAlign: TextAlign.center,
                                style: AppTypography.headlineMedium.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text,
                                  letterSpacing: -0.5,
                                ),
                              ),

                              const SizedBox(height: 8),

                              // User Greeting
                              Text(
                                'Welcome back, $displayName',
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.text2,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Status Pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _hasError
                                      ? AppColors.expenseBg
                                      : AppColors.surface2,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _hasError
                                        ? AppColors.expense.withOpacity(0.4)
                                        : AppColors.line,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isAuthenticating)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 8.0),
                                        child: SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    AppColors.accent),
                                          ),
                                        ),
                                      )
                                    else
                                      Icon(
                                        _hasError
                                            ? Icons.error_outline_rounded
                                            : Icons.touch_app_rounded,
                                        size: 14,
                                        color: _hasError
                                            ? AppColors.expense
                                            : AppColors.accent,
                                      ),
                                    if (!_isAuthenticating)
                                      const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _statusText ??
                                            'Touch fingerprint sensor or scan face',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: _hasError
                                              ? AppColors.expense
                                              : AppColors.text3,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 28),

                              // Primary Action Button (Big clear touch target)
                              SizedBox(
                                width: 240,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _isAuthenticating
                                      ? null
                                      : _promptBiometrics,
                                  icon: const Icon(Icons.fingerprint_rounded,
                                      size: 22),
                                  label: const Text(
                                    'Unlock with Biometrics',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                    foregroundColor: AppColors.onAccent,
                                    elevation: 6,
                                    shadowColor:
                                        AppColors.accent.withOpacity(0.35),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Sign Out / Switch Account Option (Anchored cleanly at bottom)
                    TextButton(
                      onPressed: () async {
                        await ref.read(authStateProvider.notifier).logout();
                        if (context.mounted) {
                          context.go('/welcome');
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      child: Text(
                        'Switch Account or Sign Out',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.text3,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.text3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
