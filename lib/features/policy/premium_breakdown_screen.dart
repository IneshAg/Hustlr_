import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';

class PremiumBreakdownScreen extends StatefulWidget {
  const PremiumBreakdownScreen({super.key});

  @override
  State<PremiumBreakdownScreen> createState() => _PremiumBreakdownScreenState();
}

class _PremiumBreakdownScreenState extends State<PremiumBreakdownScreen> {
  Map<String, dynamic>? policyData;
  String? userId;
  String userZone = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPolicyData();
  }

  Future<void> _loadPolicyData() async {
    userId = await StorageService.instance.getUserId();
    userZone = await StorageService.instance.getUserZone() ?? '';
    
    if (userId == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }
    
    try {
      final data = await ApiService.instance.getPolicyInstance(userId!);
      if (mounted) {
        setState(() {
          policyData = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isLoading) {
      return Scaffold(
        backgroundColor: theme.canvasColor,
        body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    // Safely extract breakdown
    final pb = policyData?['premium_breakdown'] as Map<String, dynamic>?;
    final int basePremium = (pb?['base'] as num?)?.toInt() ?? 49;
    final int zoneAdj = (pb?['zone_adj'] as num?)?.toInt() ?? 5;
    final int riskAdj = (pb?['risk_adj'] as num?)?.toInt() ?? 5;

    final breakdown = <String, dynamic>{
      'base_rate': basePremium,
      'zone_adjustment': zoneAdj,
      'behavioral_adjustment': riskAdj,
      'platform_discount': -3,
      'clean_history_discount': 0,
      'final_rate': policyData?['weekly_premium'] ?? 49,
      'min_bound': (basePremium * 0.7).round(),
      'max_bound': (basePremium * 2.0).round(),
      'zone_comparison': [
        {'zone': userZone.isNotEmpty ? userZone : 'Your Zone', 'rate': zoneAdj, 'risk': 'YOUR ZONE'},
        {'zone': 'T Nagar', 'rate': zoneAdj - 2, 'risk': 'MODERATE'},
        {'zone': 'OMR', 'rate': zoneAdj + 3, 'risk': 'EXTREME'},
      ],
    };
    final activePlan = policyData?['plan_name'] ?? 'Standard Shield';
    final weeklyPremium = policyData?['weekly_premium'] ?? 49;
    final userPlatform = 'Platform';


    return Scaffold(
      backgroundColor: theme.canvasColor,
      appBar: AppBar(
        leading: IconButton(icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: theme.colorScheme.onSurface), onPressed: () => context.pop()),
        title: Text('Premium Breakdown', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCurrentPlanCard(theme, isDark, activePlan, weeklyPremium, policyData),
            const SizedBox(height: 16),
            _buildCalculationCard(breakdown, theme, isDark, userZone, userPlatform, activePlan, weeklyPremium),
            const SizedBox(height: 16),
            _buildZoneComparisonCard(breakdown, theme, isDark),
            const SizedBox(height: 16),
            _buildHighRiskScenarioCard(theme, isDark),
            const SizedBox(height: 16),
            _buildPremiumBoundsCard(breakdown, theme, isDark),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPlanCard(ThemeData theme, bool isDark, String activePlan, int weeklyPremium, Map<String, dynamic>? policyData) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0C1D11) : theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(isDark ? 32 : 24),
        boxShadow: isDark ? [] : [
          BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
        ],
        border: isDark ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                activePlan,
                style: TextStyle(color: isDark ? theme.colorScheme.primary : theme.colorScheme.onPrimary, fontSize: 18, fontWeight: FontWeight.w900),
              ),
              Icon(Icons.check_circle_rounded, color: isDark ? theme.colorScheme.primary : theme.colorScheme.onPrimary, size: 24),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Policy #${policyData?['id']?.toString().toUpperCase() ?? "HS-98234-AX"}',
            style: TextStyle(color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.6) : theme.colorScheme.onPrimary.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'VALID UNTIL: ${policyData?['valid_until'] ?? "26 Oct 2026"}',
            style: TextStyle(color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.8) : theme.colorScheme.onPrimary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0),
          ),
          const SizedBox(height: 32),
          Text(
            'Personalised Weekly Rate',
            style: TextStyle(color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.6) : theme.colorScheme.onPrimary.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹$weeklyPremium',
                style: TextStyle(color: isDark ? theme.colorScheme.onSurface : theme.colorScheme.onPrimary, fontSize: 40, fontWeight: FontWeight.w900, height: 1.1),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
                child: Text(
                  '/ week',
                  style: TextStyle(color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.6) : theme.colorScheme.onPrimary.withValues(alpha: 0.8), fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: (isDark ? theme.colorScheme.onSurface : theme.colorScheme.onPrimary).withValues(alpha: 0.15), height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.event_available_rounded, size: 16, color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : theme.colorScheme.onPrimary.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text('Fixed for 91 days (quarterly) · Next review in 3 months', style: TextStyle(color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.6) : theme.colorScheme.onPrimary.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalculationCard(Map<String, dynamic> breakdown, ThemeData theme, bool isDark, String userZone, String userPlatform, String activePlan, int weeklyPremium) {
    return _SurfaceCard(
      theme: theme, isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.security_rounded, size: 16, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Text(activePlan, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹$weeklyPremium per week · Fixed price',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _CoverageTag(label: 'Rain', theme: theme),
              _CoverageTag(label: 'Heat', theme: theme),
              _CoverageTag(label: 'Pollution', theme: theme),
              _CoverageTag(label: 'App Downtime', theme: theme),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Text(
            'Price is the same for all workers on this plan. No hidden fees.',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w500),
          ),
          
          const SizedBox(height: 20),
          Text(
            'Sourced from IMD historical data, Zepto order logs, and PLFS Gig Worker Earnings Survey 2025.',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _CoverageTag({required String label, required ThemeData theme}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildZoneComparisonCard(Map<String, dynamic> breakdown, ThemeData theme, bool isDark) {
    final List<Map<String, dynamic>> zones = List<Map<String, dynamic>>.from(breakdown['zone_comparison']);
    zones.sort((a, b) => (b['rate'] as int).compareTo(a['rate'] as int));
    final int maxRate = zones.isNotEmpty ? zones.first['rate'] as int : 100;

    return _SurfaceCard(
      theme: theme, isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.public_rounded, size: 16, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Text('How Your Zone Compares', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 24),
          ...zones.map((z) {
            final double ratio = (z['rate'] as int) / maxRate;
            final String currentZ = z['zone'] as String;
            final bool isAdyar = userZone.contains(currentZ) || currentZ == userZone;
            final String note = isAdyar ? 'YOUR ZONE' : '${z['risk']} RISK';

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(currentZ, style: TextStyle(fontSize: 12, fontWeight: isAdyar ? FontWeight.w900 : FontWeight.w700, color: isAdyar ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 46,
                    child: Text('₹${z['rate']}/wk', style: TextStyle(fontSize: 12, fontWeight: isAdyar ? FontWeight.w900 : FontWeight.w700, color: isAdyar ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(height: 8, decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(4))),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(height: 10, decoration: BoxDecoration(color: isAdyar ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 60,
                    child: Text(note, textAlign: TextAlign.right, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: isAdyar ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.4), letterSpacing: 0.5)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Expanded(child: Text('Workers in Velachery pay ₹6 more per week due to higher flood exposure near Pallikaranai marshland.', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), height: 1.4))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighRiskScenarioCard(ThemeData theme, bool isDark) {
    const errorColor = Color(0xFFE57373);
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF231414) : const Color(0xFFFFF6F6),
        borderRadius: BorderRadius.circular(isDark ? 32 : 24),
        border: Border.all(color: errorColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: errorColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.warning_amber_rounded, size: 16, color: errorColor),
              ),
              const SizedBox(width: 12),
              const Text('During High-Risk Weeks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: errorColor)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'When your zone records 2+ disruption events in a week, Hustlr automatically lowers trigger thresholds by 10%:',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.8 : 0.9), height: 1.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Normal week:', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
              Text('Rain threshold → 64.5mm/hr', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface.withValues(alpha: 0.8))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('High-risk week:', style: TextStyle(fontSize: 13, color: errorColor, fontWeight: FontWeight.w800)),
              const Text('Rain threshold → 58.1mm/hr  (-10%)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: errorColor)),
            ],
          ),
          const SizedBox(height: 20),
          Text('Easier to trigger during your worst weeks — when you need it most.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.9 : 1.0))),
          const SizedBox(height: 4),
          Text('Your premium stays fixed. Only the threshold changes.', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPremiumBoundsCard(Map<String, dynamic> breakdown, ThemeData theme, bool isDark) {
    return _SurfaceCard(
      theme: theme, isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.shield_rounded, size: 16, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Text('Pricing Guardrails', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Hustlr never charges you more than 2× or less than 0.7× of your base plan rate:',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), height: 1.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Maximum this season:', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w700)),
              Text('₹${breakdown["max_bound"]}/week', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
            ],
          ),
          Text('(2.0× base plan rate)', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Minimum this season:', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w700)),
              Text('₹${breakdown["min_bound"]}/week', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
            ],
          ),
          Text('(0.7× base plan rate)', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          Text('Your rate is fixed regardless of weather forecasts or upcoming disruption risk. You always know what you pay.', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), height: 1.4, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// Reusable dynamic surface wrapper
class _SurfaceCard extends StatelessWidget {
  final Widget child;
  final ThemeData theme;
  final bool isDark;

  const _SurfaceCard({required this.child, required this.theme, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(isDark ? 32 : 24),
        boxShadow: isDark ? [] : [
          const BoxShadow(color: Color(0x05000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
        border: isDark ? Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5) : Border.all(color: Colors.black.withValues(alpha: 0.04), width: 1.5),
      ),
      child: child,
    );
  }
}
