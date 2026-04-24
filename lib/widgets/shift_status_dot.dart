import 'package:flutter/material.dart';
import 'package:app_settings/app_settings.dart';
import '../../services/shift_tracking_service.dart';

/// Animated GPS status dot shown on the Dashboard next to shift status.
/// Green = active + healthy heartbeat
/// Yellow = weak signal (accuracy > 50m)
/// Red = shift PAUSED (heartbeat lost > 120s)
class ShiftStatusDot extends StatefulWidget {
  const ShiftStatusDot({super.key});

  @override
  State<ShiftStatusDot> createState() => _ShiftStatusDotState();
}

class _ShiftStatusDotState extends State<ShiftStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    ShiftTrackingService.instance.addListener(_onShiftUpdate);
  }

  @override
  void dispose() {
    ShiftTrackingService.instance.removeListener(_onShiftUpdate);
    _pulseController.dispose();
    super.dispose();
  }

  void _onShiftUpdate() => setState(() {});

  Color get _dotColor {
    switch (ShiftTrackingService.instance.gpsStateLabel) {
      case 'active':
        return const Color(0xFF43A047);
      case 'weak':
        return const Color(0xFFFFA000);
      case 'paused':
        return const Color(0xFFE53935);
      default:
        return Colors.grey;
    }
  }

  String get _dotLabel {
    switch (ShiftTrackingService.instance.gpsStateLabel) {
      case 'active':
        return 'GPS Active';
      case 'weak':
        return 'Weak Signal';
      case 'paused':
        return 'Coverage Paused';
      default:
        return 'Offline';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _dotColor;
    final isRed = ShiftTrackingService.instance.gpsStateLabel == 'paused';

    return GestureDetector(
      onTap: isRed ? () => _showFixGpsSheet(context) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: _pulseAnim.value),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _dotLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
          if (isRed) ...[
            const SizedBox(width: 4),
            Icon(Icons.help_outline_rounded, size: 12, color: color),
          ],
        ],
      ),
    );
  }
}

void _showFixGpsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.gps_off, color: Color(0xFFE53935), size: 22),
            const SizedBox(width: 10),
            Text('Fix GPS Coverage',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          _FixStep(number: '1', text: 'Go outside or move to an open area'),
          _FixStep(
            number: '2',
            text: 'Check that Hustlr\'s battery setting is "Unrestricted"',
            onTapUpdate: () => AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization),
          ),
          _FixStep(
            number: '3',
            text: 'Make sure location is set to "Always Allow"',
            onTapUpdate: () async {
              // Deep-link directly to THIS app’s location settings
              // (avoids landing on Rapido or another app’s settings page)
              await AppSettings.openAppSettings(type: AppSettingsType.location);
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1c1f1c),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FixStep extends StatelessWidget {
  final String number;
  final String text;
  final VoidCallback? onTapUpdate;
  const _FixStep({required this.number, required this.text, this.onTapUpdate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: const Color(0xFF2E7D32),
          child: Text(number,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontSize: 13, height: 1.3)),
              if (onTapUpdate != null) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onTapUpdate,
                  child: const Text(
                    'Open Settings',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}
