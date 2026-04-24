import 'package:flutter/material.dart';

class HustlrBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const HustlrBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1a1c19) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2d302d) : const Color(0xFFE5E7EB);

    final items = [
      _NavConfig(activeIcon: Icons.shield, inactiveIcon: Icons.shield_outlined, label: 'Home'),
      _NavConfig(activeIcon: Icons.description, inactiveIcon: Icons.description_outlined, label: 'Policy'),
      _NavConfig(activeIcon: Icons.check_circle, inactiveIcon: Icons.check_circle_outline, label: 'Claims'),
      _NavConfig(activeIcon: Icons.account_balance_wallet, inactiveIcon: Icons.account_balance_wallet_outlined, label: 'Wallet'),
    ];

    return SafeArea(
      bottom: true,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            top: BorderSide(color: borderColor, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final isActive = currentIndex == index;
            final item = items[index];
            return _NavItem(
              icon: isActive ? item.activeIcon : item.inactiveIcon,
              label: item.label,
              isActive: isActive,
              isDark: isDark,
              onTap: () => onTap(index),
            );
          }),
        ),
      ),
    );
  }
}

class _NavConfig {
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;

  const _NavConfig({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
  });
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: isActive
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2E7D32) : const Color(0xFF1B5E20),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
