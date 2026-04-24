import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/location_service.dart';

class ZoneDepthIndicator extends StatelessWidget {
  const ZoneDepthIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocationService>(
      builder: (context, location, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final score = location.depthScore;
        final multiplier = location.getDepthMultiplier();
        final isTracking = location.isTracking;

        if (!isTracking) return const SizedBox.shrink();

        // Color based on depth tier
        Color zoneColor;
        String zoneLabel;
        if (score >= 0.61) {
          zoneColor = const Color(0xFF1B5E20);
          zoneLabel = 'Core Zone';
        } else if (score >= 0.21) {
          zoneColor = const Color(0xFFE65100);
          zoneLabel = 'Mid Zone';
        } else {
          zoneColor = const Color(0xFFB71C1C);
          zoneLabel = 'Edge Zone';
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1F1C) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(color: zoneColor, width: 3),
            ),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zone Position',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF91938D) : const Color(0xFF4A6741),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    zoneLabel,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: zoneColor,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Depth score bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(multiplier * 100).round()}% payout eligible',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: zoneColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                     width: 100,
                     height: 6,
                     child: ClipRRect(
                       borderRadius: BorderRadius.circular(3),
                       child: LinearProgressIndicator(
                         value: score,
                         backgroundColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8F5E9),
                         valueColor: AlwaysStoppedAnimation(zoneColor),
                       ),
                     ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
