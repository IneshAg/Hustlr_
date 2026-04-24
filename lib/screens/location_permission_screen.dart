import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../services/location_permission_service.dart';

class LocationPermissionScreen extends StatelessWidget {
  const LocationPermissionScreen({super.key});

  void _goToLogin(BuildContext context) {
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Icon ────────────────────────────────────────────────
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 52,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(height: 32),

              // ── Heading ──────────────────────────────────────────────
              const Text(
                'Enable Zone Protection',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D1B0F),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // ── Subtitle ─────────────────────────────────────────────
              const Text(
                'Hustlr monitors your delivery zone to automatically detect '
                'disruptions and trigger your payouts. Location tracking runs '
                'only during your active shift.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF4A6741),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // ── Bullet points ────────────────────────────────────────
              const _PermissionBullet(
                icon: Icons.payments_outlined,
                text:
                    'Automatic payout triggers when rain or outage hits your zone',
              ),
              const _PermissionBullet(
                icon: Icons.security,
                text:
                    'Zone depth verification protects honest workers from fraud',
              ),
              const _PermissionBullet(
                icon: Icons.battery_saver,
                text:
                    'Optimised to use minimal battery — updates every 5 minutes only',
              ),
              const SizedBox(height: 32),

              // ── Allow button ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    await LocationPermissionService
                        .requestAllLocationPermissions();
                    if (context.mounted) _goToLogin(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Enable Zone Protection →',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionBullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PermissionBullet({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF374151),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
