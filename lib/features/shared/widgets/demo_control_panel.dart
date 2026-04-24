import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../services/mock_data_service.dart';

/// Shows the demo control panel bottom sheet.
void showDemoPanel(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _DemoControlPanel(),
  );
}

class _DemoControlPanel extends StatefulWidget {
  const _DemoControlPanel();

  @override
  State<_DemoControlPanel> createState() => _DemoControlPanelState();
}

class _DemoControlPanelState extends State<_DemoControlPanel> {
  bool _isTriggering = false;

  Future<void> _trigger(void Function(MockDataService) action) async {
    if (_isTriggering) return;
    setState(() => _isTriggering = true);
    try {
      final svc = context.read<MockDataService>();
      action(svc);
      await Future.delayed(const Duration(milliseconds: 300));
    } finally {
      if (mounted) setState(() => _isTriggering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: const Border(top: BorderSide(color: Color(0xFF10B981), width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            '🎮  Demo Controls',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Manrope'),
          ),
          const SizedBox(height: 6),
          Text(
            'Trigger live claim scenarios for the demo presentation.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontFamily: 'Manrope'),
          ),
          const SizedBox(height: 20),

          _demoButton(context, '🌧  Rain Disruption', 'Triggers ₹120 parametric payout', const Color(0xFF3B82F6),
              () => _trigger((s) => s.triggerRainDisruption())),
          const SizedBox(height: 10),
          _demoButton(context, '🌡  Extreme Heat', 'Triggers ₹130 parametric payout', const Color(0xFFF59E0B),
              () => _trigger((s) => s.triggerExtremeHeat())),
          const SizedBox(height: 10),
          _demoButton(context, '📱  Platform Downtime', 'Triggers ₹140 parametric payout', const Color(0xFF8B5CF6),
              () => _trigger((s) => s.triggerPlatformDowntime())),
          const SizedBox(height: 20),

          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              side: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Close', style: TextStyle(fontFamily: 'Manrope')),
          ),
        ],
      ),
    );
  }

  Widget _demoButton(BuildContext context, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: _isTriggering ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Manrope')),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11, fontFamily: 'Manrope')),
                ],
              ),
            ),
            if (_isTriggering)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: color, strokeWidth: 2))
            else
              Icon(Icons.play_circle_outline_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}
