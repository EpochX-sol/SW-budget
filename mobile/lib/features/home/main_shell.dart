import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../activity/activity_providers.dart';

class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewCountAsync = ref.watch(reviewInboxCountProvider);
    final reviewCount = reviewCountAsync.value ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.line, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.accentBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (int index) {
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined, color: AppColors.text3),
              selectedIcon: Icon(Icons.home_rounded, color: AppColors.accent),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.format_list_bulleted_rounded, color: AppColors.text3),
              selectedIcon: Icon(Icons.format_list_bulleted_rounded, color: AppColors.accent),
              label: 'Activity',
            ),
            const NavigationDestination(
              icon: Icon(Icons.track_changes_outlined, color: AppColors.text3),
              selectedIcon: Icon(Icons.track_changes_rounded, color: AppColors.accent),
              label: 'Plan',
            ),
            const NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined, color: AppColors.text3),
              selectedIcon: Icon(Icons.bar_chart_rounded, color: AppColors.accent),
              label: 'Insights',
            ),
            NavigationDestination(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.grid_view_outlined, color: AppColors.text3),
                  if (reviewCount > 0)
                    Positioned(
                      top: -2,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$reviewCount',
                          style: const TextStyle(
                            color: Color(0xFF080C14),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              selectedIcon: const Icon(Icons.grid_view_rounded, color: AppColors.accent),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
