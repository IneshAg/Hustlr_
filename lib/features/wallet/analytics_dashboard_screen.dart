import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/claims/claims_bloc.dart';
import '../../blocs/claims/claims_event.dart';
import '../../blocs/policy/policy_bloc.dart';
import '../../blocs/policy/policy_state.dart';
import '../../models/claim.dart';
import '../../models/policy.dart';
import '../../services/mock_data_service.dart';
import '../../services/storage_service.dart';
import '../../core/router/app_router.dart';
import 'package:intl/intl.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  String _zone = '';

  String _policyAddonsLabel(Policy? policy) {
    if (policy == null || !policy.status.isCoverageActive) return 'None';

    if (policy.tier == PlanTier.full) {
      return 'Included in Full Shield';
    }

    final names = policy.riders
        .map((r) => (r['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();

    if (names.isEmpty) return 'None';
    return names.join(', ');
  }

  DateTime _parseDemoClaimDate(ClaimModel claim) {
    if (claim.date.toLowerCase() == 'just now') return DateTime.now();
    for (final pattern in ['yyyy-MM-dd', 'MMM d, yyyy', 'dd MMM yyyy']) {
      try {
        return DateFormat(pattern).parse(claim.date);
      } catch (_) {}
    }
    return DateTime.now();
  }

  int _demoClaimHours(ClaimModel claim) {
    if (claim.durationHours != null && claim.durationHours! > 0) {
      return claim.durationHours!;
    }
    final gross = claim.grossAmount ?? claim.amount;
    return gross <= 0 ? 1 : (gross / 40).round().clamp(1, 6);
  }

  @override
  void initState() {
    super.initState();
    // Load claims data when analytics screen opens
    final userId = StorageService.userId;
    context.read<ClaimsBloc>().add(LoadClaims(userId));
      
    StorageService.instance.getUserZone().then((z) {
      if (mounted) setState(() => _zone = z ?? '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bgScreen = isDark ? const Color(0xFF0a0b0a) : const Color(0xFFF4F6F4);
    final green    = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final primary  = isDark ? Colors.white : const Color(0xFF0D1B0F);

    return Scaffold(
      backgroundColor: bgScreen,
      appBar: AppBar(
        backgroundColor: bgScreen,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: primary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'My Protection Analytics',
          style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildHeroCard(context, isDark, green, primary),
                const SizedBox(height: 16),
                _buildPolicyInfoCard(context, isDark, green, primary),
                const SizedBox(height: 16),
                _buildDisruptionChart(context, isDark, green, primary),
                const SizedBox(height: 16),
                _buildPayoutHistory(context, isDark, green, primary),
                const SizedBox(height: 16),
                _buildUpgradeNudge(context, isDark, green, primary),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Returns the quarterly policy expiry — 3 months from today — formatted as "Mon YYYY".
  String _quarterlyExpiry() {
    final expiry = DateTime.now().add(const Duration(days: 90));
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[expiry.month - 1]} ${expiry.year}';
  }

  Widget _buildHeroCard(BuildContext context, bool isDark, Color green, Color primary) {
    final userZone = _zone.replaceAll(RegExp(r' dark store zone', caseSensitive: false), '')
                          .replaceAll(RegExp(r' zone', caseSensitive: false), '').trim();
    final heroBg = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final subText = isDark ? Colors.white70 : Colors.black54;

    final claimsState = context.watch<ClaimsBloc>().state;
    final claims = claimsState.claims;
    final mockClaims = context.watch<MockDataService>().claims;
    
    final userId = StorageService.userId;
    final isDemoSession =
        userId.startsWith('DEMO_') ||
        userId.startsWith('demo-') ||
        userId.startsWith('mock-') ||
        StorageService.getString('isDemoSession') == 'true';

    int total = 0;
    int count = 0;
    if (isDemoSession && mockClaims.isNotEmpty) {
      for (final c in mockClaims) {
        if (c.status.toUpperCase() != 'REJECTED') {
          total += c.grossAmount ?? c.amount;
          count++;
        }
      }
    } else {
      for (var c in claims) {
        if (c.status != ClaimStatus.rejected) {
          total += c.grossPayout;
          count++;
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: heroBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: heroBg.withValues(alpha: 0.25),
            blurRadius: 20, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total income protected this month',
            style: TextStyle(color: subText, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            '₹$total',
            style: TextStyle(color: primary, fontSize: 36, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Across $count disruption event${count == 1 ? '' : 's'} in $userZone',
            style: TextStyle(color: subText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyInfoCard(BuildContext context, bool isDark, Color green, Color primary) {
    final cardBg = isDark ? const Color(0xFF1c1f1c) : Colors.white;

    return BlocBuilder<PolicyBloc, PolicyState>(
      builder: (context, policyState) {
        String getPlanDisplayName(PlanTier? tier) {
          if (tier == null) return 'No Active Plan';
          switch (tier) {
            case PlanTier.basic:
              return 'Basic Shield';
            case PlanTier.standard:
              return 'Standard Shield';
            case PlanTier.full:
              return 'Full Shield';
          }
        }

        final activePlanName = getPlanDisplayName(policyState.activePolicy?.tier);
        final hasActivePolicy = policyState.activePolicy != null && policyState.activePolicy!.status.isCoverageActive;
        final addonLabel = _policyAddonsLabel(policyState.activePolicy);

        // Only show the policy info card if there's an active policy
        if (!hasActivePolicy) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                'No active protection plan. Tap "Upgrade" to buy a shield.',
                style: TextStyle(color: primary, fontSize: 13, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _buildPolicyRow(context, isDark, green, primary, title: 'Active Plan', value: activePlanName, chip: 'Active'),
              const SizedBox(height: 12),
              _buildPolicyRow(context, isDark, green, primary, title: 'Policy Valid', value: _quarterlyExpiry()),
              const SizedBox(height: 12),
              _buildPolicyRow(context, isDark, green, primary, title: 'Add-ons', value: addonLabel),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPolicyRow(BuildContext context, bool isDark, Color green, Color primary, {
    required String title,
    required String value,
    String? chip,
  }) {
    final text = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final btnTxt = isDark ? const Color(0xFF0A0B0A) : Colors.white;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w400)),
        Row(
          children: [
            Text(value, style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w600)),
            if (chip != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(12)),
                child: Text(chip, style: TextStyle(color: btnTxt, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildDisruptionChart(BuildContext context, bool isDark, Color green, Color primary) {
    final text = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final empty = isDark ? Colors.white24 : Colors.black12;
    final orange = const Color(0xFFFF9800);
    final blue = const Color(0xFF2196F3);
    final cardBg = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final userId = StorageService.userId;
    final isDemoSession =
        userId.startsWith('DEMO_') ||
        userId.startsWith('demo-') ||
        userId.startsWith('mock-') ||
        StorageService.getString('isDemoSession') == 'true';
    final mockClaims = context.watch<MockDataService>().claims;

    final rain = List<int>.filled(7, 0);
    final heat = List<int>.filled(7, 0);
    final platform = List<int>.filled(7, 0);

    if (isDemoSession && mockClaims.isNotEmpty) {
      for (final claim in mockClaims) {
      if (claim.status.toUpperCase() == 'REJECTED') continue;
      final idx = _parseDemoClaimDate(claim).weekday - 1;
      final hours = _demoClaimHours(claim);
      final type = claim.type.toLowerCase();
      if (type.contains('rain')) {
        rain[idx] += hours;
      } else if (type.contains('heat')) {
        heat[idx] += hours;
      } else {
        platform[idx] += hours;
      }
      }
    }

    List<BarChartGroupData> groups() {
      return List.generate(7, (index) {
        final total = rain[index] + heat[index] + platform[index];
        Color color = empty;
        if (total > 0) {
          if (rain[index] >= heat[index] && rain[index] >= platform[index]) {
            color = green;
          } else if (heat[index] >= platform[index]) {
            color = orange;
          } else {
            color = blue;
          }
        }
        return _buildBarGroup(index, total, color);
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Disruption hours this week',
            style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                barGroups: groups(),
                titlesData: FlTitlesData(
                  leftTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(days[value.toInt()],
                              style: TextStyle(color: text.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w500)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
                barTouchData: BarTouchData(enabled: false),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(context, 'Rain',     green, isDark),
              const SizedBox(width: 16),
              _buildLegendItem(context, 'Heat',     const Color(0xFFFF9800), isDark),
              const SizedBox(width: 16),
              _buildLegendItem(context, 'Platform', const Color(0xFF2196F3), isDark),
            ],
          ),
        ],
      ),
    );
  }

  BarChartGroupData _buildBarGroup(int x, int y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y.toDouble(),
          color: color,
          width: 20,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ],
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color, bool isDark) {
    final text = isDark ? Colors.white70 : Colors.black54;
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildPayoutHistory(BuildContext context, bool isDark, Color green, Color primary) {
    final text = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final userZone = _zone.replaceAll(RegExp(r' dark store zone', caseSensitive: false), '')
                          .replaceAll(RegExp(r' zone', caseSensitive: false), '').trim();

    final claimsState = context.watch<ClaimsBloc>().state;
    final claims = claimsState.claims;
    final mockClaims = context.watch<MockDataService>().claims;
    final userId = StorageService.userId;
    final isDemoSession =
        userId.startsWith('DEMO_') ||
        userId.startsWith('demo-') ||
        userId.startsWith('mock-') ||
        StorageService.getString('isDemoSession') == 'true';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payout history', style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if ((!isDemoSession || mockClaims.isEmpty) && claims.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Text(
                'No recent payouts to show.',
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          )
        else if (isDemoSession && mockClaims.isNotEmpty)
          ...mockClaims.take(3).map((claim) {
            IconData icon;
            final type = claim.type.toLowerCase();
            if (type.contains('rain')) {
              icon = Icons.water_drop_rounded;
            } else if (type.contains('heat')) {
              icon = Icons.wb_sunny_rounded;
            } else {
              icon = Icons.phonelink_off_rounded;
            }

            Color statusColor;
            switch (claim.status.toUpperCase()) {
              case 'APPROVED': statusColor = green; break;
              case 'REJECTED': statusColor = Colors.red; break;
              case 'PROCESSING': statusColor = const Color(0xFF2196F3); break;
              default: statusColor = const Color(0xFFFF9800); break;
            }

            final dateStr = DateFormat('MMM d, yyyy').format(_parseDemoClaimDate(claim));

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildPayoutCard(
                context, isDark, green, primary,
                icon: icon,
                trigger: claim.type,
                date: dateStr,
                zone: claim.zone.isNotEmpty ? claim.zone : userZone,
                amount: '₹${claim.grossAmount ?? claim.amount}',
                status: claim.status,
                statusColor: statusColor,
              ),
            );
          })
        else
          ...claims.take(3).map((claim) {
            IconData icon;
            if (claim.triggerType.contains('rain')) {
              icon = Icons.water_drop_rounded;
            } else if (claim.triggerType.contains('heat')) {
              icon = Icons.wb_sunny_rounded;
            } else {
              icon = Icons.phonelink_off_rounded;
            }
            
            Color statusColor;
            switch (claim.status) {
              case ClaimStatus.approved: statusColor = green; break;
              case ClaimStatus.rejected: statusColor = Colors.red; break;
              case ClaimStatus.processing: statusColor = const Color(0xFF2196F3); break;
              case ClaimStatus.flagged: statusColor = Colors.orange; break;
              default: statusColor = const Color(0xFFFF9800); break;
            }

            final dateStr = DateFormat('MMM d, yyyy').format(claim.createdAt);
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildPayoutCard(
                context, isDark, green, primary,
                icon: icon, 
                trigger: claim.displayLabel,
                date: dateStr, 
                zone: userZone, 
                amount: '₹${claim.grossPayout}',
                status: claim.status.displayLabel, 
                statusColor: statusColor
              ),
            );
          }),
      ],
    );
  }

  Widget _buildPayoutCard(BuildContext context, bool isDark, Color green, Color primary, {
    required IconData icon,
    required String trigger,
    required String date,
    required String zone,
    required String amount,
    required String status,
    required Color statusColor,
  }) {
    final text = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final sub = isDark ? Colors.white70 : Colors.black54;
    final iconBg = isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF4F4EF);
    final cardBg = isDark ? const Color(0xFF1c1f1c) : Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trigger, style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$date • $zone', style: TextStyle(color: sub, fontSize: 12, fontWeight: FontWeight.w400)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount, style: TextStyle(color: green, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeNudge(BuildContext context, bool isDark, Color green, Color primary) {
    final text = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final btnTxt = isDark ? const Color(0xFF0A0B0A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1c1f1c) : Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: green.withValues(alpha: isDark ? 0.4 : 1.0)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'Upgrade to Full Shield to cover bandh and internet blackouts',
            style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push(AppRoutes.policy),
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                foregroundColor: btnTxt,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Upgrade Now',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: btnTxt)),
            ),
          ),
        ],
      ),
    );
  }
}
