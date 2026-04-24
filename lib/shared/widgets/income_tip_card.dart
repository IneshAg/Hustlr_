import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IncomeTipCard extends StatefulWidget {
  const IncomeTipCard({super.key});

  @override
  State<IncomeTipCard> createState() => _IncomeTipCardState();
}

class _IncomeTipCardState extends State<IncomeTipCard> {
  bool _isVisible = false;
  int _tipIndex = 0;
  int _sessionCount = 0;

  static const List<Map<String, dynamic>> _tips = [
    {
      'icon': Icons.access_time_rounded,
      'title': 'Earn more during peak hours',
      'body': 'Morning 8–11 AM and evening 5–9 PM have the highest order density in your zone. Consistent peak-hour deliveries build a stronger income history.',
    },
    {
      'icon': Icons.security_rounded,
      'title': 'Stay covered through monsoon season',
      'body': 'Chennai\'s northeast monsoon runs October to December. Workers with active coverage during the full season receive payouts automatically when rain thresholds are crossed.',
    },
    {
      'icon': Icons.location_on_rounded,
      'title': 'Stay close to your dark store',
      'body': 'Orders are assigned based on proximity to the Zepto dark store. Staying within your delivery radius means faster assignment and more deliveries per shift.',
    },
    {
      'icon': Icons.bolt_rounded,
      'title': 'Activate coverage before the week starts',
      'body': 'Coverage activates on Monday and covers disruptions through Sunday. Activating mid-week means pro-rata coverage only — activate Monday morning for full protection.',
    },
    {
      'icon': Icons.trending_up_rounded,
      'title': 'Consistent weeks build a stronger profile',
      'body': 'Workers who maintain active coverage across multiple consecutive weeks are eligible for the claim-free cashback on Full Shield.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _checkShouldShowTip();
  }

  Future<void> _checkShouldShowTip() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCount = prefs.getInt('session_count') ?? 0;
    _sessionCount++;
    await prefs.setInt('session_count', _sessionCount);
    if (_sessionCount % 3 != 1) return;
    final lastTipShown = prefs.getInt('last_tip_shown') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const fortyEightHours = 48 * 60 * 60 * 1000;
    if (now - lastTipShown < fortyEightHours) return;
    _tipIndex = prefs.getInt('tip_index') ?? 0;
    setState(() { _isVisible = true; });
  }

  Future<void> _dismissTip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_tip_shown', DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt('tip_index', (_tipIndex + 1) % _tips.length);
    setState(() { _isVisible = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tip = _tips[_tipIndex];

    // Theme-aware colors
    final cardBg       = isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF0FFF4);
    final accentBorder = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final iconBg       = isDark ? const Color(0xFF004734) : const Color(0xFFE8F5E9);
    final primaryColor = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final titleColor   = theme.colorScheme.onSurface;
    final bodyColor    = isDark ? const Color(0xFF91938D) : const Color(0xFF4A6741);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: accentBorder, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  tip['icon'] as IconData,
                  color: primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'INCOME TIP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _dismissTip,
                child: Icon(
                  Icons.close,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tip['title'] as String,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tip['body'] as String,
            style: TextStyle(
              fontSize: 13,
              color: bodyColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
