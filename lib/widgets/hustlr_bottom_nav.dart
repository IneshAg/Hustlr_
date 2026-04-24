import 'package:flutter/material.dart';

class HustlrBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const HustlrBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const List<_NavConfig> _items = [
    _NavConfig(icon: Icons.shield_outlined, label: 'HOME'),
    _NavConfig(icon: Icons.article_outlined, label: 'POLICY'),
    _NavConfig(icon: Icons.verified_user_outlined, label: 'CLAIMS'),
    _NavConfig(icon: Icons.grid_view_rounded, label: 'WALLET'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1a1c19) : Colors.white;
    final activeColor = isDark ? const Color(0xFF3fff8b) : const Color(0xFF1B5E20);
    final inactiveColor = isDark ? const Color(0xFF91938d) : const Color(0xFF8FAE8B);
    final activeTextColor = isDark ? const Color(0xFF3fff8b) : const Color(0xFF1B5E20);
    final shadowColor = isDark ? Colors.black.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.1);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 40,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(_items.length, (index) {
            final isActive = currentIndex == index;
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isActive ? activeColor : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _items[index].icon,
                        color: isActive
                            ? (isDark ? const Color(0xFF0a0b0a) : Colors.white)
                            : inactiveColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _items[index].label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: isActive ? activeTextColor : inactiveColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
        ),
      ),
    );
  }
}

class _NavConfig {
  final IconData icon;
  final String label;
  const _NavConfig({required this.icon, required this.label});
}
