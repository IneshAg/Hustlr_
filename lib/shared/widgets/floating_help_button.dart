import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';

class FloatingHelpButton extends StatelessWidget {
  const FloatingHelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1B5E20);
    final iconColor = isDark ? const Color(0xFF0A0B0A) : Colors.white;
    final shadowColor = isDark
        ? const Color(0xFF3FFF8B).withValues(alpha: 0.25)
        : const Color(0xFF1B5E20).withValues(alpha: 0.40);

    return Positioned(
      right: 16,
      bottom: 80,
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.support),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: isDark ? 20 : 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.headset_mic_rounded,
            color: iconColor,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// Wrap any Scaffold body with this to automatically include
/// the FloatingHelpButton in a Stack.
class ScaffoldWithHelp extends StatelessWidget {
  final Widget child;
  const ScaffoldWithHelp({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const FloatingHelpButton(),
      ],
    );
  }
}
