import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    // Safety net: if router redirect doesn't fire for any reason,
    // leave splash after a short delay instead of hanging indefinitely.
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      context.go(AppRoutes.login);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor    = theme.scaffoldBackgroundColor;
    final green      = theme.colorScheme.primary;
    final iconBgOuter = green.withValues(alpha: 0.15);
    final iconBgInner = isDark ? const Color(0xFF004734) : const Color(0xFFDCE8DC);
    final titleColor  = theme.colorScheme.onSurface;
    final subColor    = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final trackFill   = green;
    final trackEmpty  = isDark ? const Color(0xFF2A2D2A) : const Color(0xFFD1D5DB);
    final helpIconFg  = isDark ? const Color(0xFF0A0B0A) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ── Centered content ───────────────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconBgOuter,
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: iconBgInner,
                      borderRadius: BorderRadius.circular(32),
                    ),
                    alignment: Alignment.center,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/icon.png',
                        width: 72,
                        height: 72,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.shield_rounded,
                          size: 72,
                          color: green,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Hustlr',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your income.\nProtected.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: subColor,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom progress indicator ───────────────────────────────────────
          Positioned(
            left: 0, right: 0, bottom: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80, height: 4,
                  decoration: BoxDecoration(
                    color: trackFill,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 60, height: 4,
                  decoration: BoxDecoration(
                    color: trackEmpty,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),

          // ── Floating help button ───────────────────────────────────────────
          Positioned(
            right: 20, bottom: 20,
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: green,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: green.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.headset_mic_rounded,
                color: helpIconFg,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
