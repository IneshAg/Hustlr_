import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/pdf_generator.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/app_events.dart';
import '../../services/storage_service.dart';
import '../../shared/widgets/mobile_container.dart';
import '../../shared/widgets/offline_banner.dart';
import '../../shared/widgets/animated_skeleton.dart';
import 'package:provider/provider.dart';
import '../../services/mock_data_service.dart';

// ─── Plan Data ────────────────────────────────────────────────────────────────
class _Plan {
  final String id;
  final String name;
  final String subtitle;
  final String price;
  final bool accentLeft;
  final bool isMostPopular;
  final bool isElite;

  const _Plan({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.price,
    this.accentLeft = false,
    this.isMostPopular = false,
    this.isElite = false,
  });
}

List<_Plan> _getPlans(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return [
    _Plan(
      id: 'basic',
      name: l10n.policy_basic,
      subtitle: 'Rain + extreme heat cover',
      price: 'Rs.35/wk',
      accentLeft: true,
    ),
    _Plan(
      id: 'standard',
      name: l10n.policy_standard,
      subtitle: 'Everything in Basic + platform downtime + severe AQI',
      price: 'Rs.49/wk',
      accentLeft: true,
      isMostPopular: true,
    ),
    _Plan(
      id: 'full',
      name: l10n.policy_full,
      subtitle: 'Everything in Standard + bandh/curfew + internet blackout',      
      price: 'Rs.79/wk',
      accentLeft: true,
      isElite: true,
    ),
  ];
}

class _Rider {
  final IconData icon;
  final String name;
  final String price;
  final bool defaultOn;
  final int cost;

  const _Rider({required this.icon, required this.name, required this.price, required this.defaultOn, this.cost = 0});
}

const _riders = [
  _Rider(icon: Icons.groups_rounded,        name: 'Bandh / Curfew',    price: '+₹15/wk', defaultOn: false),
  _Rider(icon: Icons.wifi_off_rounded,      name: 'Internet Blackout', price: '+₹12/wk', defaultOn: false),
];

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _normalizePlanTier(dynamic raw) {
  final s = raw?.toString().toLowerCase().trim() ?? '';
  if (s.contains('full')) return 'full';
  if (s.contains('basic')) return 'basic';
  return 'standard';
}

int _planBasePremium(String tier) {
  if (tier == 'full') return 79;
  if (tier == 'basic') return 35;
  return 49;
}

int _planWeeklyPayoutCap(String tier) {
  if (tier == 'full') return 500;
  if (tier == 'basic') return 210;
  return 340;
}

int _planDailyPayoutCap(String tier) {
  if (tier == 'full') return 250;
  if (tier == 'basic') return 100;
  return 150;
}

int? _asPositiveInt(dynamic raw) {
  if (raw == null) return null;
  final value = raw is num ? raw.toInt() : int.tryParse(raw.toString());
  if (value == null || value <= 0) return null;
  if (value >= 10000) return (value / 100).round();
  return value;
}

int _resolveWeeklyCap(Map<String, dynamic>? policy, String tier) {
  final fromPolicy = _asPositiveInt(
      policy?['max_weekly_payout'] ?? policy?['max_weekly_payout_paise']);
  return fromPolicy ?? _planWeeklyPayoutCap(tier);
}

int _resolveDailyCap(Map<String, dynamic>? policy, String tier) {
  final fromPolicy = _asPositiveInt(
      policy?['max_daily_payout'] ?? policy?['max_daily_payout_paise']);
  return fromPolicy ?? _planDailyPayoutCap(tier);
}

List<String> _coverageTitlesForPolicy(Map<String, dynamic>? policy) {
  final tier = _normalizePlanTier(policy?['plan_tier'] ?? policy?['plan_name']);
  final titles = <String>[];

  void add(String name) {
    if (!titles.contains(name)) titles.add(name);
  }

  add('Heavy Rain');
  add('Extreme Heat');

  if (tier == 'standard' || tier == 'full') {
    add('Severe AQI');
    add('Platform Downtime');
  }

  if (tier == 'full') {
    add('Bandh / Curfew');
    add('Internet Blackout');
    add('Traffic Congestion');
    add('Cyclone Landfall');
  }

  final riders = policy?['riders'] as List<dynamic>?;
  if (riders != null) {
    for (final rider in riders) {
      if (rider is! Map) continue;
      final mapped = _coverageFromRiderName(rider['name']?.toString() ?? '');
      final title = mapped?['title']?.toString();
      if (title != null && title.isNotEmpty) add(title);
    }
  }

  return titles;
}

int _riderCostFromName(String riderName) {
  final n = riderName.toLowerCase();
  if (n.contains('bandh') || n.contains('curfew') || n.contains('strike')) return 15;
  if (n.contains('internet') || n.contains('blackout')) return 12;
  return 0;
}

bool _isRiderIncludedInPlan(String tier, String riderName) {
  if (tier == 'full') return true;
  return false;
}

int _billableRiderTotal(String tier, List<dynamic>? riders) {
  if (riders == null || riders.isEmpty) return 0;

  var total = 0;
  for (final r in riders) {
    if (r is! Map) continue;
    final name = r['name']?.toString() ?? '';
    if (name.isEmpty || _isRiderIncludedInPlan(tier, name)) continue;

    final explicitCost = (r['cost'] as num?)?.toInt();
    final resolvedCost = (explicitCost != null && explicitCost > 0)
        ? explicitCost
        : _riderCostFromName(name);
    total += resolvedCost;
  }
  return total;
}

int _billableRiderCount(String tier, List<dynamic>? riders) {
  if (riders == null || riders.isEmpty) return 0;

  var count = 0;
  for (final r in riders) {
    if (r is! Map) continue;
    final name = r['name']?.toString() ?? '';
    if (name.isEmpty || _isRiderIncludedInPlan(tier, name)) continue;

    final explicitCost = (r['cost'] as num?)?.toInt();
    final resolvedCost = (explicitCost != null && explicitCost > 0)
        ? explicitCost
        : _riderCostFromName(name);
    if (resolvedCost > 0) count++;
  }
  return count;
}

int _effectiveWeeklyPremiumFromPolicy(Map<String, dynamic> item) {
  final tier = _normalizePlanTier(item['plan_tier'] ?? item['plan_name']);
  final base = _planBasePremium(tier);
  final riders = item['riders'] as List<dynamic>?;
  final computed = base + _billableRiderTotal(tier, riders);

  final raw = item['weekly_premium'];
  final stored = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');

  if (stored != null && stored >= computed && stored <= 200) {
    return stored.round();
  }
  return computed;
}

Map<String, dynamic>? _coverageFromRiderName(String riderName) {
  final n = riderName.toLowerCase();
  if (n.contains('cyclone')) {
    return {
      'key': 'cyclone',
      'icon': Icons.cyclone_rounded,
      'title': 'Cyclone Coverage',
      'subtitle': 'Severe cyclone warnings',
    };
  }
  if (n.contains('bandh') || n.contains('curfew') || n.contains('strike')) {
    return {
      'key': 'curfew',
      'icon': Icons.groups_rounded,
      'title': 'Curfew & Strikes',
      'subtitle': 'Work stoppages covered',
    };
  }
  if (n.contains('internet') || n.contains('blackout')) {
    return {
      'key': 'blackout',
      'icon': Icons.wifi_off_rounded,
      'title': 'Internet Blackout',
      'subtitle': 'Connectivity disruption cover',
    };
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  POLICY SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class PolicyScreen extends StatefulWidget {
  const PolicyScreen({super.key});

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? activePolicy;
  List<Map<String, dynamic>> policyHistory = [];
  bool isLoading = true;
  StreamSubscription<void>? _policySub;
  StreamSubscription<void>? _walletSub;
  bool _isLoadingPolicy = false;
  int _activeDays = 0;
  bool _isCheckingEligibility = true;
  DateTime? _lastLoadTime;
  static const _loadDebounceMs = 1500;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _tabController.addListener(_onTabChanged);
    _loadPolicy();
    _policySub = AppEvents.instance.onPolicyUpdated.listen((_) => _forceReload());
    _walletSub = AppEvents.instance.onWalletUpdated.listen((_) => _forceReload());
  }

  void _onTabChanged() {
    // Reload when user switches to History tab (index 2)
    if (_tabController.index == 2) _forceReload();
  }

  void _forceReload() {
    _lastLoadTime = null;
    _isLoadingPolicy = false;
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    final now = DateTime.now();
    if (_lastLoadTime != null && now.difference(_lastLoadTime!).inMilliseconds < _loadDebounceMs) {
      return;
    }
    _lastLoadTime = now;

    if (_isLoadingPolicy) return;
    _isLoadingPolicy = true;
    try {
      final uid = await StorageService.instance.getUserId();
      if (uid != null) {
        final data = await ApiService.instance.getPolicy(uid);
        if (mounted) {
          final rawPolicy = data['policy'];
          final rawHistory = data['history'];
          final wasInactive = activePolicy == null;

          final mock = context.read<MockDataService>();
          var policyToUse = rawPolicy is Map<String, dynamic> ? rawPolicy : null;
          
          final isDemoUser = uid.startsWith('DEMO_') ||
              uid.startsWith('demo-') ||
              uid.startsWith('mock-') ||
              StorageService.getString('isDemoSession') == 'true';

          if (policyToUse == null && isDemoUser && mock.hasActivePolicy) {
            final tier = mock.activePolicy.plan.split(' ')[0].toLowerCase();
            policyToUse = {
              'id': 'MOCK-${uid.hashCode}',
              'plan_tier': tier,
              'plan_name': mock.activePolicy.plan,
              'status': 'active',
              'weekly_premium': mock.activePolicy.premium,
              'coverage_start': mock.activePolicy.coverageStart,
              'commitment_end': mock.activePolicy.coverageEnd,
              'riders': mock.activePolicy.riders.map((r) => {'name': r}).toList(),
              'created_at': mock.activePolicy.coverageStart,
            };
          }

          setState(() {
            activePolicy = policyToUse;
            policyHistory = rawHistory is List
                ? rawHistory.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
                : [];
            isLoading = false;
            if (wasInactive && activePolicy != null) {
              Future.microtask(() => _tabController.animateTo(0));
            }
          });

          try {
            final profile = await ApiService.instance.getWorkerById(uid);
            if (mounted) {
              setState(() {
                _activeDays = profile['active_days'] ?? 0;
                _isCheckingEligibility = false;
              });
            }
          } catch (_) {
            if (mounted) setState(() => _isCheckingEligibility = false);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() {
        isLoading = false;
        _isCheckingEligibility = false;
      });
    } finally {
      _isLoadingPolicy = false;
    }
  }

  @override
  void dispose() {
    _policySub?.cancel();
    _walletSub?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF141614) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.dashboard),
        ),
        title: const Text('Hustlr Shield', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: green,
          unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          indicatorColor: green,
          tabs: const [
            Tab(text: 'Current Plan'),
            Tab(text: 'Upgrade'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: MobileContainer(
              child: isLoading 
                  ? _buildPolicySkeleton() 
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _CurrentPlanTab(activePolicy: activePolicy),
                        _UpgradeTab(
                          onProceed: () => context.push(AppRoutes.checkout, extra: {'amount': 79.0, 'planName': 'Full Shield'}),
                          activePolicy: activePolicy,
                          activeDays: _activeDays,
                        ),
                        _LiveHistoryTab(
                          activePolicy: activePolicy,
                          policyHistory: policyHistory,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicySkeleton() {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          AnimatedSkeleton(height: 140, width: double.infinity, borderRadius: 16),
          SizedBox(height: 24),
          AnimatedSkeleton(height: 24, width: 120, borderRadius: 6),
          SizedBox(height: 16),
          AnimatedSkeleton(height: 80, width: double.infinity, borderRadius: 12),
          SizedBox(height: 12),
          AnimatedSkeleton(height: 80, width: double.infinity, borderRadius: 12),
        ],
      ),
    );
  }
}

// ─── Current Plan Tab ────────────────────────────────────────────────────────
class _CurrentPlanTab extends StatefulWidget {
  final Map<String, dynamic>? activePolicy;
  const _CurrentPlanTab({this.activePolicy});

  @override
  State<_CurrentPlanTab> createState() => _CurrentPlanTabState();
}

class _CurrentPlanTabState extends State<_CurrentPlanTab> {
  bool _coverageExpanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.activePolicy == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No active shield found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Upgrade to start your protection', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final coverageItems = _getCoverageItems(widget.activePolicy);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, 'ACTIVE COVERAGE'),
          const SizedBox(height: 12),
          _ActiveCoverageCard(activePolicy: widget.activePolicy),
          
          // 7-Day Waiting Period Notice
          _buildWaitingPeriodNotice(),

          const SizedBox(height: 24),
          _buildCoverageHeader(),
          if (_coverageExpanded) 
            ...coverageItems.map((item) => _buildCoverageItem(item)),
          
          const SizedBox(height: 20),
          _policyDisclosureCard(context),
        ],
      ),
    );
  }

  Widget _buildWaitingPeriodNotice() {
    final createdAtStr = widget.activePolicy!['created_at']?.toString();
    if (createdAtStr == null) return const SizedBox.shrink();
    
    final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
    final daysSinceStart = DateTime.now().difference(createdAt).inDays;
    
    if (daysSinceStart < 7) {
      final daysLeft = 7 - daysSinceStart;
      return Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined, color: Colors.orange, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Waiting Period Active', 
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('Payouts are enabled after 7 days of protection. $daysLeft days remaining.',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCoverageHeader() {
    return GestureDetector(
      onTap: () => setState(() => _coverageExpanded = !_coverageExpanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('COVERAGE DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            Row(
              children: [
                const Text('View', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Icon(_coverageExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverageItem(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1F1C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? theme.dividerColor : Colors.grey.shade200),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B4332).withValues(alpha: 0.4) : const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(item['icon'] as IconData, color: theme.primaryColor, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(item['subtitle'] as String, style: TextStyle(fontSize: 13, color: isDark ? Colors.grey : Colors.black54)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.primaryColor,
          ),
          child: const Icon(Icons.check, size: 16, color: Colors.white),
        ),
      ]),
    );
  }

  List<Map<String, dynamic>> _getCoverageItems(Map<String, dynamic>? policy) {
    final tier = _normalizePlanTier(policy?['plan_tier'] ?? policy?['plan_name']);
    final items = <Map<String, dynamic>>[];
    
    items.add({'icon': Icons.water_drop, 'title': 'Rain Disruption', 'subtitle': 'Triggers when rain > 3hrs'});
    items.add({'icon': Icons.wb_sunny, 'title': 'Extreme Heat', 'subtitle': 'Triggers above 42°C'});
    
    if (tier == 'standard' || tier == 'full') {
      items.add({'icon': Icons.air, 'title': 'Pollution Alert', 'subtitle': 'AQI > 200'});
      items.add({'icon': Icons.phonelink_off, 'title': 'Platform Downtime', 'subtitle': 'Outages over 90 mins'});
    }
    
    if (tier == 'full') {
      items.add({'icon': Icons.gavel, 'title': 'Bandh & Curfew', 'subtitle': 'City-wide shutdowns'});
      items.add({'icon': Icons.wifi_off, 'title': 'Internet Blackout', 'subtitle': 'Network connectivity loss'});
    }
    
    return items;
  }
}

// ─── Upgrade Tab ─────────────────────────────────────────────────────────────
class _UpgradeTab extends StatefulWidget {
  final VoidCallback? onProceed;
  final Map<String, dynamic>? activePolicy;
  final int activeDays;
  const _UpgradeTab({this.onProceed, this.activePolicy, this.activeDays = 0});

  @override
  State<_UpgradeTab> createState() => _UpgradeTabState();
}

class _UpgradeTabState extends State<_UpgradeTab> {
  String _selectedPlan = 'standard';
  final Map<String, bool> _riderToggles = {
    'Bandh / Curfew': false,
    'Internet Blackout': false,
  };

  final List<_Rider> _riders = [
    _Rider(name: 'Bandh / Curfew', icon: Icons.groups_rounded, price: '+₹15/wk', cost: 15, defaultOn: false),
    _Rider(name: 'Internet Blackout', icon: Icons.wifi_off_rounded, price: '+₹12/wk', cost: 12, defaultOn: false),
  ];

  List<_Plan> _getPlans(BuildContext context) {
    return [
      _Plan(
        id: 'basic',
        name: 'Basic Shield',
        subtitle: 'Rain & heat protection only',
        price: '₹35/wk',
        accentLeft: true,
      ),
      _Plan(
        id: 'standard',
        name: 'Standard Shield',
        subtitle: 'Everything in Basic + platform downtime + severe AQI',
        price: '₹49/wk',
        isMostPopular: true,
        accentLeft: true,
      ),
      _Plan(
        id: 'full',
        name: 'Full Shield',
        subtitle: 'Everything in Standard + bandh/curfew + internet blackout',
        price: '₹79/wk',
        isElite: true,
      ),
    ];
  }

  int _planBasePremium(String id) {
    switch (id) {
      case 'basic': return 35;
      case 'standard': return 49;
      case 'full': return 79;
      default: return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = _getPlans(context);
    final total = _calculateTotal();

    // ── Quarterly lock logic ─────────────────────────────────────────────────
    // Determine the current plan tier so we can disable downgrade/same-tier.
    final currentTierStr = (widget.activePolicy?['plan_tier'] as String? ??
            widget.activePolicy?['plan_name'] as String? ??
            '')
        .toLowerCase()
        .replaceAll(' shield', '').trim();
    const tierRank = {'basic': 1, 'standard': 2, 'full': 3};
    final currentRank = tierRank[currentTierStr] ?? 0;
    final hasActivePolicy = widget.activePolicy != null &&
        (widget.activePolicy!['status']?.toString().toLowerCase() == 'active');

    // Auto-select the next tier above the current one on first build
    // so the button is immediately in a valid state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (hasActivePolicy && tierRank[_selectedPlan] != null &&
          tierRank[_selectedPlan]! <= currentRank) {
        final nextTier = tierRank.entries
            .where((e) => e.value > currentRank)
            .fold<MapEntry<String,int>?>(null,
                (best, e) => best == null || e.value < best.value ? e : best);
        if (nextTier != null) setState(() => _selectedPlan = nextTier.key);
      }
    });

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.activeDays < 5 && !hasActivePolicy) _buildProbationNotice(),
                if (hasActivePolicy && currentRank > 0 && currentRank < 3)
                  _buildUpgradeOnlyBanner(currentTierStr),
                _sectionLabel(context, 'CHOOSE A SHIELD'),
                const SizedBox(height: 12),
                ...plans.map((p) {
                  final planRank = tierRank[p.id] ?? 0;
                  final isQuarterlyLocked = hasActivePolicy && planRank <= currentRank;
                  return _PlanCard(
                    plan: p,
                    isSelected: _selectedPlan == p.id,
                    isQuarterlyLocked: isQuarterlyLocked,
                    currentTier: currentTierStr,
                    isLocked: !hasActivePolicy && (p.id == 'standard' || p.id == 'full') && widget.activeDays < 5,
                    activeDays: widget.activeDays,
                    onTap: isQuarterlyLocked
                        ? null
                        : () => setState(() => _selectedPlan = p.id),
                  );
                }),
                const SizedBox(height: 24),
                if (_selectedPlan == 'standard' || _selectedPlan == 'full') ...[
                  _sectionLabel(context, 'INCOME ADD-ONS'),
                  const SizedBox(height: 12),
                  if (_selectedPlan == 'full')
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Full Shield already includes all add-ons.',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                    )
                  else
                    ..._riders.map((r) => _RiderRow(
                          rider: r,
                          value: _riderToggles[r.name] ?? false,
                          onChanged: (v) => setState(() => _riderToggles[r.name] = v),
                        )),
                ],
                const SizedBox(height: 24),
                _buildCoverageRules(),
                const SizedBox(height: 16),
                _buildPayoutFAQ(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        _buildActionSection(total, isUpgrade: hasActivePolicy && currentRank > 0),
      ],
    );
  }

  Widget _buildUpgradeOnlyBanner(String currentTier) {
    final tierLabel = currentTier == 'basic' ? 'Basic Shield'
        : currentTier == 'standard' ? 'Standard Shield' : 'Full Shield';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock_outlined, color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Colors.amber, height: 1.4),
                children: [
                  const TextSpan(text: 'Quarterly commitment active. ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: 'You are on $tierLabel. Downgrading is locked for 91 days. You can upgrade to a higher tier any time.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  int _calculateTotal() {
    int t = _planBasePremium(_selectedPlan);
    if (_selectedPlan == 'standard') {
      if (_riderToggles['Bandh / Curfew']!) t += 15;
      if (_riderToggles['Internet Blackout']!) t += 12;
    }
    return t;
  }

  Widget _buildProbationNotice() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.security, color: Colors.red, size: 20),
              SizedBox(width: 12),
              Text('Underwriting Lock', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('New partners are restricted to Basic Shield for the first 5 days.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (widget.activeDays / 5).clamp(0.0, 1.0),
            backgroundColor: Colors.red.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation(Colors.red),
          ),
          const SizedBox(height: 6),
          Text('${widget.activeDays} of 5 days completed', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }


  Widget _buildCoverageRules() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('Coverage Rules',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          leading: const Icon(Icons.gavel_rounded, size: 20),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _ruleItem('45-minute minimum', 'disruption must last 45 continuous minutes'),
            _ruleItem('24-hour cooling period', 'same trigger cannot fire again within 24 hours'),
            _ruleItem('Shift overlap required', 'disruption must overlap shift by minimum 2 hours'),
            _ruleItem('Post-activation only', 'events before activation are never covered'),
            _ruleItem('Multi-event coverage enabled', 'Full Shield supports multiple trigger payouts, including compound disruptions'),
            _ruleItem('Manual Disruption Filing', 'For disruptions not covered by automated triggers, report within 24 hours via Claims. Subject to evidence review.'),
          ],
        ),
      ),
    );
  }

  Widget _ruleItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13),
                children: [
                  TextSpan(text: '$title — ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  TextSpan(text: desc, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutFAQ() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('Payout Limits & FAQs',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          leading: const Icon(Icons.payments_rounded, size: 20),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _faqItem('What are the weekly payout caps?',
                'Basic Shield: ₹210/week · Standard Shield: ₹340/week · Full Shield: ₹500/week'),
            _faqItem('What are the daily payout caps?',
                'Basic Shield: ₹100/day · Standard Shield: ₹150/day · Full Shield: ₹250/day'),
            _faqItem('How long is a plan valid?',
                'All Hustlr Shield plans are quarterly — 13 weeks (91 days). The weekly premium is auto-debited each week from your wallet.'),
            _faqItem('When do payouts hit my wallet?',
                'Automatically within 2–4 hours of a verified disruption event during your shift.'),
            _faqItem('Can the same disruption pay out multiple times?',
                'No. A 24-hour cooling period applies per trigger type. Full Shield supports compound triggers (multiple different events on the same day).'),
            _faqItem('What counts as a valid shift overlap?',
                'The disruption must overlap your active delivery window by at least 2 continuous hours.'),
          ],
        ),
      ),
    );
  }

  Widget _faqItem(String question, String answer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Q: $question', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(answer, style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildActionSection(int total, {bool isUpgrade = false}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('WEEKLY PREMIUM',
                    style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('₹$total',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const Text('/week', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              context.push(AppRoutes.checkout, extra: {
                'amount': total.toDouble(),
                'planName': _selectedPlan.toUpperCase(),
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isUpgrade ? const Color(0xFF0D47A1) : const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              elevation: 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isUpgrade ? 'Upgrade' : 'Proceed to',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.2)),
                    Text(isUpgrade ? 'Plan' : 'Payment',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.2)),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(isUpgrade ? Icons.arrow_upward_rounded : Icons.arrow_forward_rounded, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── History Tab ─────────────────────────────────────────────────────────────
class _LiveHistoryTab extends StatelessWidget {
  final Map<String, dynamic>? activePolicy;
  final List<Map<String, dynamic>> policyHistory;

  const _LiveHistoryTab({this.activePolicy, this.policyHistory = const []});

  @override
  Widget build(BuildContext context) {
    // Build combined list: current active policy first, then history
    final allItems = <Map<String, dynamic>>[];
    if (activePolicy != null) allItems.add({...activePolicy!, '_isCurrent': true});
    allItems.addAll(policyHistory.where((h) => h['id'] != activePolicy?['id']));

    if (allItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('No policy history yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Your policies will appear here once activated.', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        final isCurrent = item['_isCurrent'] == true;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final tier = _normalizePlanTier(item['plan_tier'] ?? item['plan_name']);
        final planLabel = item['plan_name']?.toString() ?? tier.toUpperCase();
        final premium = item['weekly_premium']?.toString() ?? '-';
        final status = (item['status']?.toString() ?? '-').toUpperCase();
        final weeklyCap = _planWeeklyPayoutCap(tier);
        final dailyCap = _planDailyPayoutCap(tier);

        // Format dates
        String dateRange = '-';
        final start = DateTime.tryParse(item['created_at']?.toString() ?? '');
        final end = DateTime.tryParse(item['commitment_end']?.toString() ?? '');
        if (start != null) {
          final endDate = end ?? start.add(const Duration(days: 91));
          dateRange = '${start.day}/${start.month}/${start.year} – ${endDate.day}/${endDate.month}/${endDate.year}';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isCurrent
                ? (isDark ? const Color(0xFF1B3A2A) : const Color(0xFFE8F5E9))
                : (isDark ? const Color(0xFF1C1F1C) : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent
                  ? theme.primaryColor.withValues(alpha: 0.5)
                  : (isDark ? theme.dividerColor : Colors.grey.shade200),
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1B4332).withValues(alpha: 0.4) : const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.shield_rounded, color: theme.primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(planLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(dateRange, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₹$premium/wk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.primaryColor)),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? theme.primaryColor.withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isCurrent ? 'ACTIVE' : status,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isCurrent ? theme.primaryColor : Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _capChip('Wkly cap', '₹$weeklyCap', theme),
                    const SizedBox(width: 8),
                    _capChip('Daily cap', '₹$dailyCap', theme),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _capChip(String label, String value, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2D2A) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ─── Shared Components ────────────────────────────────────────────────────────

class _ActiveCoverageCard extends StatelessWidget {
  final Map<String, dynamic>? activePolicy;
  const _ActiveCoverageCard({this.activePolicy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1B4332) : const Color(0xFF1B5E20);
    
    final policyId = activePolicy?['id']?.toString() ?? '-';
    final planName = activePolicy?['plan_name'] ?? 'Standard Shield';
    final rawPremium = activePolicy?['weekly_premium'];
    final premium = rawPremium != null ? rawPremium.toString() : '49';
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(planName, 
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    Text('Policy #$policyId', 
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.verified, color: cardBg, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('QUARTERLY VALIDITY', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7), letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Text(_formatValidity(activePolicy), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WEEKLY PREMIUM', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7), letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('₹$premium', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        const Text('/wk', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('PAYOUT CAPS', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7), letterSpacing: 1.0)),
                  const SizedBox(height: 4),
                  Text('₹${_resolveWeeklyCap(activePolicy, _normalizePlanTier(activePolicy?["plan_tier"] ?? activePolicy?["plan_name"]))}/wk', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text('₹${_resolveDailyCap(activePolicy, _normalizePlanTier(activePolicy?["plan_tier"] ?? activePolicy?["plan_name"]))}/day', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Policy details button
          InkWell(
            onTap: () {
              final p = activePolicy;
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) {
                  final sheetDark = Theme.of(context).brightness == Brightness.dark;
                  final sheetBg = sheetDark ? const Color(0xFF1C1F1C) : Colors.white;
                  final sheetTextColor = Theme.of(context).colorScheme.onSurface;
                  final divColor = sheetDark ? Colors.white12 : Colors.grey.shade200;

                  Widget row(String label, String value) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label, style: TextStyle(color: sheetTextColor.withValues(alpha: 0.55), fontSize: 13, fontWeight: FontWeight.w500)),
                        Flexible(child: Text(value, textAlign: TextAlign.end, style: TextStyle(color: sheetTextColor, fontSize: 13, fontWeight: FontWeight.w700))),
                      ],
                    ),
                  );

                  final riders = p?['riders'] as List<dynamic>?;
                  final riderNames = riders?.map((r) => r['name']?.toString() ?? '').where((s) => s.isNotEmpty).join(', ');

                  return Container(
                    padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
                    decoration: BoxDecoration(
                      color: sheetBg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                        const SizedBox(height: 20),
                        Text('Policy Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: sheetTextColor)),
                        const SizedBox(height: 4),
                        Text('Your active protection summary', style: TextStyle(fontSize: 13, color: sheetTextColor.withValues(alpha: 0.5))),
                        const SizedBox(height: 16),
                        Divider(color: divColor),
                        row('Policy ID', policyId),
                        Divider(color: divColor, height: 1),
                        row('Plan Name', planName),
                        Divider(color: divColor, height: 1),
                        row('Plan Tier', (p?['plan_tier']?.toString() ?? '-').toUpperCase()),
                        Divider(color: divColor, height: 1),
                        row('Status', (p?['status']?.toString() ?? '-').toUpperCase()),
                        Divider(color: divColor, height: 1),
                        row('Weekly Premium', '₹$premium/week'),
                        Divider(color: divColor, height: 1),
                        row('Validity', _formatValidity(p)),
                        Divider(color: divColor, height: 1),
                        () {
                          final tier = _normalizePlanTier(p?['plan_tier'] ?? p?['plan_name']);
                          return row('Max Weekly Payout', '₹${_resolveWeeklyCap(p, tier)}');
                        }(),
                        Divider(color: divColor, height: 1),
                        () {
                          final tier = _normalizePlanTier(p?['plan_tier'] ?? p?['plan_name']);
                          return row('Max Daily Payout', '₹${_resolveDailyCap(p, tier)}');
                        }(),
                        if (riderNames != null && riderNames.isNotEmpty) ...[
                          Divider(color: divColor, height: 1),
                          row('Add-ons', riderNames),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                },
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('POLICY DETAILS', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11, letterSpacing: 0.5)),
                  const Row(
                    children: [
                      Text('View', style: TextStyle(color: Colors.white, fontSize: 13)),
                      SizedBox(width: 4),
                      Icon(Icons.open_in_new_rounded, color: Colors.white, size: 14),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => PdfGenerator.generateAndPreviewCertificate(
                    name: StorageService.getString('userName') ?? 'Hustlr Worker',
                    zone: StorageService.userZone.isNotEmpty ? StorageService.userZone : 'Your Zone',
                    planName: planName,
                    policyNumber: policyId,
                    coverageStart: DateTime.tryParse(activePolicy?['created_at']?.toString() ?? ''),
                    coverageEnd: DateTime.tryParse(activePolicy?['commitment_end']?.toString() ?? ''),
                    weeklyPremium: int.tryParse(premium) ?? 49,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                  label: const Text('Download Certificate', style: TextStyle(color: Colors.white, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatValidity(Map<String, dynamic>? policy) {
    if (policy == null) return '-';
    final start = DateTime.tryParse(policy['created_at']?.toString() ?? '') ?? DateTime.now();
    // Quarterly = 13 weeks = 91 days
    final end = DateTime.tryParse(policy['commitment_end']?.toString() ?? '') ?? start.add(const Duration(days: 91));
    return '${start.day}/${start.month}/${start.year} – ${end.day}/${end.month}/${end.year} (13 wks)';
  }
}

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final bool isSelected;
  final bool isLocked;           // 5-day probation lock (new users, no policy)
  final bool isQuarterlyLocked;  // 91-day downgrade lock (existing policyholders)
  final String currentTier;      // e.g. 'basic', 'standard'
  final int activeDays;
  final VoidCallback? onTap;

  const _PlanCard({
    required this.plan,
    required this.isSelected,
    required this.onTap,
    this.isLocked = false,
    this.isQuarterlyLocked = false,
    this.currentTier = '',
    this.activeDays = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isElite = plan.isElite;
    final isDark = theme.brightness == Brightness.dark;
    final anyLock = isLocked || isQuarterlyLocked;
    final isEliteActive = isElite && !anyLock;

    // Determine subtitle/label
    String subtitleText;
    Color subtitleColor;
    Widget? lockIcon;

    if (isQuarterlyLocked) {
      final isCurrent = plan.id == currentTier;
      subtitleText = isCurrent ? '✓ Your current plan' : 'Quarterly locked — upgrade only';
      subtitleColor = isCurrent ? Colors.green.shade400 : Colors.grey;
      lockIcon = isCurrent
          ? null
          : const Icon(Icons.lock_outline, size: 14, color: Colors.grey);
    } else if (isLocked) {
      subtitleText = 'Unlocks in ${5 - activeDays} days';
      subtitleColor = Colors.red;
      lockIcon = const Icon(Icons.lock, size: 14, color: Colors.red);
    } else {
      subtitleText = plan.subtitle;
      subtitleColor = isEliteActive
          ? Colors.white.withValues(alpha: 0.8)
          : Colors.grey;
      lockIcon = null;
    }

    return GestureDetector(
      onTap: anyLock ? null : onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: anyLock
                  ? (isDark ? const Color(0xFF1C1F1C).withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.5))
                  : (isElite ? const Color(0xFFFF8C00) : (isDark ? const Color(0xFF1C1F1C) : Colors.white)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                  ? (isEliteActive ? Colors.white : theme.primaryColor)
                  : (isDark ? theme.dividerColor : Colors.grey.shade300),
                width: isSelected ? 2 : 1),
              boxShadow: isSelected && !isDark && !anyLock ? [BoxShadow(color: theme.primaryColor.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))] : null,
            ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (plan.accentLeft)
                      Container(width: 4, color: isEliteActive ? Colors.white.withValues(alpha: 0.5) : theme.primaryColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Text(plan.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: anyLock
                                              ? Colors.grey
                                              : (isEliteActive ? Colors.white : theme.textTheme.titleLarge?.color)
                                        )),
                                      if (lockIcon != null) ...[ const SizedBox(width: 8), lockIcon ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(subtitleText,
                                      style: TextStyle(fontSize: 13, color: subtitleColor)),
                                  if (isElite && !anyLock) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                      child: const Text('10% CASHBACK', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap: () => context.push(AppRoutes.compoundTriggers),
                                      child: const Text('Learn about compound triggers →',
                                          style: TextStyle(color: Colors.white, fontSize: 11, decoration: TextDecoration.underline)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Text(plan.price,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: anyLock ? Colors.grey : (isEliteActive ? Colors.white : theme.primaryColor)
                                )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (plan.isMostPopular && !isQuarterlyLocked)
            Positioned(
              top: 0,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F5A40),
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                ),
                child: const Text('MOST POPULAR', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            ),
          if (plan.isElite && !isQuarterlyLocked)
            Positioned(
              top: 0,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8))),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, color: Colors.orange, size: 10),
                    SizedBox(width: 4),
                    Text('BEST VALUE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RiderRow extends StatelessWidget {
  final _Rider rider;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RiderRow({required this.rider, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(rider.icon, color: theme.colorScheme.primary),
        ),
        title: Text(rider.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        subtitle: Text(rider.price),
        trailing: Transform.scale(
          scale: 0.8,
          child: Switch(
            value: value, 
            onChanged: onChanged,
            activeTrackColor: theme.primaryColor,
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final Color textColor;

  const _GhostButton({required this.onPressed, required this.child, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: textColor.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: child,
    );
  }
}

Widget _policyDisclosureCard(BuildContext context) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  return InkWell(
    onTap: () => context.push(AppRoutes.insuranceCompliance),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B4332).withValues(alpha: 0.4) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? theme.colorScheme.primary.withValues(alpha: 0.3) : const Color(0xFFC8E6C9)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Insurance & data disclosure', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text('IRDAI norms, DPDP, triggers & payouts — tap to read', 
                     style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    ),
  );
}


Widget _sectionLabel(BuildContext context, String text) {
  return Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2));
}

