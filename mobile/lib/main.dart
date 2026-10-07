import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/device/background_sync_coordinator.dart';
import 'core/router/app_router.dart';
import 'core/security/auth_state.dart';
import 'core/theme/app_theme.dart';
import 'data/sms/ingestion_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: SwBudgetApp(),
    ),
  );
}

class SwBudgetApp extends ConsumerStatefulWidget {
  const SwBudgetApp({super.key});

  @override
  ConsumerState<SwBudgetApp> createState() => _SwBudgetAppState();
}

class _SwBudgetAppState extends ConsumerState<SwBudgetApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final authNotifier = ref.read(authStateProvider.notifier);
    if (state == AppLifecycleState.paused) {
      authNotifier.handleAppPause();
    } else if (state == AppLifecycleState.resumed) {
      authNotifier.handleAppResume();
      // Phase 3: Execute foreground catch-up scan for any financial SMS arrived while asleep
      ref.read(backgroundSyncCoordinatorProvider.future).then((coordinator) {
        coordinator.executeForegroundCatchUp();
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Eagerly maintain active listener for real-time incoming SMS and push notifications
    ref.watch(ingestionPipelineProvider);

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'SW-budget',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
