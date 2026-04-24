import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';

import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import 'package:provider/provider.dart';
import '../../services/mock_data_service.dart';


class ShadowPolicyScreen extends StatefulWidget {
  const ShadowPolicyScreen({super.key});

  @override
  State<ShadowPolicyScreen> createState() => _ShadowPolicyScreenState();
}

class _ShadowPolicyScreenState extends State<ShadowPolicyScreen> {
  bool _loading = true;
  Map<String, dynamic>? _live;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = await StorageService.instance.getUserId();

    // ── Demo Shadow Sync ────────────────────────────────────────────────────
    final mock = Provider.of<MockDataService>(context, listen: false);
    if (mock.worker.id.startsWith('DEMO_')) {
      if (mounted) {
        setState(() {
          _live = {
            'missed_payout_inr': mock.missedAmount,
            'standard_premium_fortnight_inr': 98, // ₹49 * 2
            'net_benefit_inr': mock.missedAmount - 98,
            'events': mock.shadowEvents.map((e) => {
              'trigger_type': e.triggerIcon,
              'display_name': e.triggerName,
              'disruption_date': e.date,
              'potential_payout_inr': e.claimableAmount,
            }).toList(),
          };
          _loading = false;
        });
      }
      return;
    }

    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final data = await ApiService.instance.getShadowSummary(uid);
    if (!mounted) return;
    setState(() {
      _live = data.isNotEmpty ? data : null;
      _loading = false;
    });
  }

  int _missedInr() {
    final m = _live?['missed_payout_inr'];
    if (m is num) return m.round();
    return 0;
  }

  int _fortnightPremium() {
    final p = _live?['standard_premium_fortnight_inr'];
    if (p is num) return p.round();
    return 98;
  }

  int _netBenefit() {
    final n = _live?['net_benefit_inr'];
    if (n is num) return n.round();
    return 0;
  }

  int _eventCount() {
    final e = _live?['events'];
    if (e is List) return e.length;
    return 0;
  }

  List<Map<String, dynamic>> _events() {
    final e = _live?['events'];
    if (e is List) {
      return e.map((x) => Map<String, dynamic>.from(x as Map)).toList();
    }
    return [];
  }

  int _weeklyCta() {
    final w = (_fortnightPremium() / 2).round();
    return w > 0 ? w : 49;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green = theme.colorScheme.primary;
    final bg = theme.scaffoldBackgroundColor;
    final btnTxt = isDark ? const Color(0xFF0A0B0A) : Colors.white;
    final subText = isDark ? const Color(0xFF91938D) : const Color(0xFF4A6741);

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: theme.colorScheme.onSurface),
            onPressed: () => context.pop(),
          ),
          title: Text('What You Missed',
              style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700)),
          backgroundColor: Colors.transparent,
          foregroundColor: theme.colorScheme.onSurface,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: theme.colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text('What You Missed',
            style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF004734) : const Color(0xFF125117),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: green.withValues(alpha: isDark ? 0.15 : 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    "If you'd had Standard Shield this fortnight:",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹${_missedInr()}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold),
                  ),
                  const Text('in missed payouts',
                      style: TextStyle(color: Colors.white70)),
                  if (_live != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Live estimate from disruptions in your zone',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65), fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _shadowStat('₹${_fortnightPremium()}', 'Premium cost\n(2 weeks)'),
                      _shadowStat('₹${_netBenefit()}', 'Net benefit'),
                      _shadowStat('${_eventCount()}', 'Disruption events'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Events while uninsured:',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: theme.colorScheme.onSurface)),
            const SizedBox(height: 12),
            ..._events().map((e) => _buildMissedEventCard(context, e)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push(AppRoutes.policy),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: btnTxt,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  'Activate Standard Shield — ₹${_weeklyCta()}/wk',
                  style: TextStyle(
                      color: btnTxt,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text('Coverage starts next Monday',
                  style: TextStyle(color: subText, fontSize: 12)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _shadowStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildMissedEventCard(BuildContext context, Map<String, dynamic> event) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = theme.cardColor;
    final border =
        isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E7EB);
    final redBg = isDark ? const Color(0xFF2D0011) : const Color(0xFFFFEBEE);
    final red = isDark ? const Color(0xFFFF6B6B) : const Color(0xFFB71C1C);
    final text = theme.colorScheme.onSurface;
    final sub = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    final missed = event['missed'] ?? event['claimableAmount'];
    final amt = missed is num ? missed.round().toString() : missed?.toString() ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: redBg, shape: BoxShape.circle),
                child: Icon(Icons.close_rounded, color: red, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (event['triggerName'] ?? event['trigger'] ?? 'Event')
                        .toString(),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: text),
                  ),
                  Text(
                    (event['date'] ?? '').toString(),
                    style: TextStyle(fontSize: 12, color: sub),
                  ),
                ],
              ),
            ],
          ),
          Text(
            '₹$amt',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: text),
          ),
        ],
      ),
    );
  }
}
