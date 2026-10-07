import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../security/auth_state.dart';
import '../../features/onboarding/welcome_screen.dart';
import '../../features/onboarding/login_screen.dart';
import '../../features/onboarding/register_screen.dart';
import '../../features/onboarding/biometric_lock_screen.dart';
import '../../features/onboarding/battery_optimization_screen.dart';
import '../../features/home/main_shell.dart';
import '../../features/home/home_screen.dart';
import '../../features/activity/activity_screen.dart';
import '../../features/activity/review_inbox_screen.dart';
import '../../features/plan/plan_screen.dart';
import '../../features/insights/insights_screen.dart';
import '../../features/ai_chat/ai_chat_screen.dart';
import '../../features/ai_chat/ai_memory_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _activityNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'activity');
final _planNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'plan');
final _insightsNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'insights');
final _coachNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'coach');

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen<AuthState>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
  }
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/welcome',
    refreshListenable: notifier,
    redirect: (BuildContext context, GoRouterState state) {
      final status = authState.status;
      final location = state.uri.path;

      // Allow initial load
      if (status == AuthStatus.initial) {
        return null;
      }

      final isAuthRoute = location == '/welcome' ||
          location == '/login' ||
          location == '/register';

      // 1. Unauthenticated users must stay on onboarding screens
      if (status == AuthStatus.unauthenticated) {
        return isAuthRoute ? null : '/welcome';
      }

      // 2. Biometric locked users must be gated on lock screen
      if (status == AuthStatus.biometricLocked) {
        return location == '/biometric-lock' ? null : '/biometric-lock';
      }

      // 3. Authenticated users cannot stay on onboarding or lock screens
      if (status == AuthStatus.authenticated) {
        if (isAuthRoute || location == '/biometric-lock') {
          return '/home';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/biometric-lock',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const BiometricLockScreen(),
      ),
      GoRoute(
        path: '/review-inbox',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ReviewInboxScreen(),
      ),
      GoRoute(
        path: '/ai-memory',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AiMemoryScreen(),
      ),
      GoRoute(
        path: '/battery-guidance',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const BatteryOptimizationScreen(),
      ),

      // Bottom Navigation Shell
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeNavigatorKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _activityNavigatorKey,
            routes: [
              GoRoute(
                path: '/activity',
                builder: (context, state) => const ActivityScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _planNavigatorKey,
            routes: [
              GoRoute(
                path: '/plan',
                builder: (context, state) => const PlanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _insightsNavigatorKey,
            routes: [
              GoRoute(
                path: '/insights',
                builder: (context, state) => const InsightsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _coachNavigatorKey,
            routes: [
              GoRoute(
                path: '/coach',
                builder: (context, state) => const AiChatScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
