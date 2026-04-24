import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../widgets/hustlr_bottom_nav.dart';

/// Shell wrapper used by GoRouter's ShellRoute.
/// Renders floating bottom nav + floating help button over the child screen.
class ScaffoldWithNav extends StatelessWidget {
  final Widget child;
  final String location;

  const ScaffoldWithNav({
    super.key,
    required this.child,
    required this.location,
  });

  int _selectedIndex(String loc) {
    if (loc.startsWith('/policy'))   return 1;
    if (loc.startsWith('/claims'))   return 2;
    if (loc.startsWith('/wallet'))   return 3;
    return 0; // dashboard
  }

  @override
  Widget build(BuildContext context) {
    final idx = _selectedIndex(location);
    
    // Extracted path without query parameters
    final path = location.split('?').first;
    // Only show bottom nav bar on root tabs
    final showNavBar = [
      AppRoutes.dashboard,
      AppRoutes.policy,
      AppRoutes.claims,
      AppRoutes.wallet,
    ].contains(path);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: child,
          ),

        ],
      ),
      bottomNavigationBar: showNavBar
          ? HustlrBottomNav(
              currentIndex: idx,
              onTap: (i) {
                final routes = [
                  AppRoutes.dashboard,
                  AppRoutes.policy,
                  AppRoutes.claims,
                  AppRoutes.wallet,
                ];
                context.go(routes[i]);
              },
            )
          : null,
    );
  }
}


// ─── Dual-Mode Floating Bottom Nav Bar ───────────────────────────────────────
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? const Color(0xFF141614) : Colors.white;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.6)
        : Colors.black.withValues(alpha: 0.1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _NavItem(icon: Icons.shield_outlined,         label: 'HOME',   index: 0, current: currentIndex, onTap: onTap),
            _NavItem(icon: Icons.article_outlined,        label: 'POLICY', index: 1, current: currentIndex, onTap: onTap),
            _NavItem(icon: Icons.verified_user_outlined,  label: 'CLAIMS', index: 2, current: currentIndex, onTap: onTap),
            _NavItem(icon: Icons.grid_view_rounded,       label: 'WALLET', index: 3, current: currentIndex, onTap: onTap),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive      = index == current;
    final isDark        = Theme.of(context).brightness == Brightness.dark;
    final activeColor   = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1B5E20);
    final inactiveColor = isDark ? const Color(0xFF91938D) : const Color(0xFF8FAE8B);
    final activeIconFg  = isDark ? const Color(0xFF0A0B0A) : Colors.white;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive ? activeColor : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? activeIconFg : inactiveColor,
              size: 22,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isActive ? activeColor : inactiveColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
