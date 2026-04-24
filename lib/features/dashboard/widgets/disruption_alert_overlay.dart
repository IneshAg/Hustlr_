import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';

/// Rapido-style full-screen disruption alert overlay.
/// Shown when a disruption hits the worker's zone while they are online.
/// Auto-dismisses after [_countdownSeconds] seconds.
class DisruptionAlertOverlay extends StatefulWidget {
  final String triggerType;
  final String zone;
  final int estimatedPayout;
  final VoidCallback? onDismiss;

  const DisruptionAlertOverlay({
    super.key,
    required this.triggerType,
    required this.zone,
    required this.estimatedPayout,
    this.onDismiss,
  });

  /// Push as a full-screen transparent route so the dashboard is still
  /// partially visible behind the dark scrim.
  static Future<void> show(
    BuildContext context, {
    required String triggerType,
    required String zone,
    required int estimatedPayout,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (ctx, anim, secondaryAnim) => DisruptionAlertOverlay(
        triggerType: triggerType,
        zone: zone,
        estimatedPayout: estimatedPayout,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  State<DisruptionAlertOverlay> createState() => _DisruptionAlertOverlayState();
}

class _DisruptionAlertOverlayState extends State<DisruptionAlertOverlay>
    with SingleTickerProviderStateMixin {
  static const _countdownSeconds = 8;
  int _remaining = _countdownSeconds;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        widget.onDismiss?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  _DisruptionMeta _getMeta() {
    final t = widget.triggerType.toLowerCase();
    if (t.contains('heat') || t.contains('temperature')) {
      return _DisruptionMeta(
        icon: Icons.wb_sunny_rounded,
        label: 'EXTREME HEAT ALERT',
        color: const Color(0xFFFF6F00),
        gradient: const [Color(0xFFFF6F00), Color(0xFFE65100)],
      );
    } else if (t.contains('aqi') || t.contains('pollution')) {
      return _DisruptionMeta(
        icon: Icons.air_rounded,
        label: 'AIR QUALITY WARNING',
        color: const Color(0xFF7B1FA2),
        gradient: const [Color(0xFF7B1FA2), Color(0xFF4A148C)],
      );
    } else if (t.contains('platform') || t.contains('downtime')) {
      return _DisruptionMeta(
        icon: Icons.cloud_off_rounded,
        label: 'PLATFORM DOWNTIME',
        color: const Color(0xFF00796B),
        gradient: const [Color(0xFF00796B), Color(0xFF004D40)],
      );
    }
    // Default: rain
    return _DisruptionMeta(
      icon: Icons.thunderstorm_rounded,
      label: 'HEAVY RAIN ALERT',
      color: const Color(0xFF1565C0),
      gradient: const [Color(0xFF1976D2), Color(0xFF0D47A1)],
    );
  }

  String get _cleanZone {
    var z = widget.zone
        .replaceAll(RegExp(r' dark store zone', caseSensitive: false), '')
        .replaceAll(RegExp(r' zone', caseSensitive: false), '')
        .trim();
    return z.isEmpty ? 'Your Zone' : z;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final meta = _getMeta();
    final screenH = MediaQuery.of(context).size.height;

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: screenH * 0.72),
          decoration: const BoxDecoration(
            color: Color(0xFF0D1117),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ──────────────────────────────────────────────
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // ── Pulsing icon ─────────────────────────────────────────────
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Transform.scale(
                  scale: _pulseAnim.value,
                  child: child,
                ),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: meta.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: meta.color.withValues(alpha: 0.45),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(meta.icon, color: Colors.white, size: 38),
                ),
              ),
              const SizedBox(height: 20),

              // ── Alert label ──────────────────────────────────────────────
              Text(
                meta.label,
                style: TextStyle(
                  color: meta.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  fontFamily: 'Manrope',
                ),
              ),
              const SizedBox(height: 8),

              // ── Zone ─────────────────────────────────────────────────────
              Text(
                _cleanZone,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Manrope',
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Disruption detected in your shift zone',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),

              // ── Payout card ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        meta.color.withValues(alpha: 0.15),
                        meta.color.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: meta.color.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ESTIMATED PAYOUT',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${widget.estimatedPayout}',
                            style: TextStyle(
                              color: meta.color,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Manrope',
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'AUTO-CLAIM',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: const Color(0xFF4CAF50)
                                      .withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Buttons ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    // Dismiss with countdown
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: widget.onDismiss,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white60,
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Dismiss (${_remaining}s)',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // View claim CTA
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            widget.onDismiss?.call();
                            context.push(AppRoutes.claims);
                          },
                          icon: const Icon(Icons.receipt_long_rounded, size: 18),
                          label: const Text(
                            'View Claim',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: meta.color,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisruptionMeta {
  final IconData icon;
  final String label;
  final Color color;
  final List<Color> gradient;

  _DisruptionMeta({
    required this.icon,
    required this.label,
    required this.color,
    required this.gradient,
  });
}
