import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primary.withOpacity(0.3),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          onDestinationSelected: (int index) {
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.home_rounded, color: AppColors.primaryLight),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.receipt_long_rounded, color: AppColors.primaryLight),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.savings_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.savings_rounded, color: AppColors.primaryLight),
              label: 'Plan',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.insights_rounded, color: AppColors.primaryLight),
              label: 'Insights',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined, color: AppColors.textSecondary),
              selectedIcon: Icon(Icons.auto_awesome_rounded, color: AppColors.secondaryLight),
              label: 'Coach',
            ),
          ],
        ),
      ),
    );
  }
}
