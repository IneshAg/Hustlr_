import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/storage_service.dart';
import '../../services/api_service.dart';
import '../../services/app_events.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/biometric_service.dart';
import '../../shared/widgets/mobile_container.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/language_switcher.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api_health_service.dart';
import '../../core/router/app_router.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/auth_service.dart';
import '../../widgets/demo_controls_sheet.dart';
import '../../services/mock_data_service.dart';
import '../../services/location_service.dart';
import '../../services/background_heartbeat_service.dart';
import '../../services/shift_tracking_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _worker;
  Map<String, dynamic>? _policy;
  Map<String, dynamic>? _trustProfile = {
    'score': 124,
    'tier': {'label': '🥇 Gold'},
    'clean_weeks': 3,
    'cashback_earned': 49,
  };
  bool _isLoading = true;
  bool _biometricEnabled = false;
  bool _isOffDuty = false;
  StreamSubscription<void>? _policySub;
  StreamSubscription<void>? _claimSub;
  StreamSubscription<void>? _walletSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _policySub = AppEvents.instance.onPolicyUpdated.listen((_) => _loadData());
    _claimSub = AppEvents.instance.onClaimUpdated.listen((_) => _loadData());
    _walletSub = AppEvents.instance.onWalletUpdated.listen((_) => _loadData());
  }

  @override
  void dispose() {
    _policySub?.cancel();
    _claimSub?.cancel();
    _walletSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final userId = await StorageService.instance.getUserId();
    
    // Prioritize mock data for demo consistency
    final mockSvc = Provider.of<MockDataService>(context, listen: false);
    if (mockSvc.worker.id.startsWith('DEMO_')) {
      if (mounted) {
        setState(() {
          _worker = {
            'id': mockSvc.worker.id,
            'name': mockSvc.worker.name,
            'platform': mockSvc.worker.platform,
            'city': mockSvc.worker.city,
            'zone': mockSvc.worker.zone,
          };
          _policy = {
            'plan_tier': mockSvc.activePolicy.plan.split(' ')[0].toLowerCase(),
            'status': mockSvc.activePolicy.status,
          };
          _isLoading = false;
        });
      }
      return;
    }

    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    
    try {
      final rawWorker = await ApiService.instance
          .getWorkerById(userId)
          .timeout(const Duration(seconds: 12), onTimeout: () => <String, dynamic>{});
      final worker = Map<String, dynamic>.from(rawWorker);
      
      final localName = await StorageService.instance.getUserName();
      final localPhone = await StorageService.instance.getPhone();
      final localZone = await StorageService.instance.getUserZone();
      final localCity = await StorageService.instance.getUserCity();
      
      worker['name'] = worker['name'] ?? localName;
      worker['phone'] = worker['phone'] ?? localPhone;
      worker['zone'] = worker['zone'] ?? localZone;
      worker['city'] = worker['city'] ?? localCity;

      Map<String, dynamic>? policy;
      Map<String, dynamic>? trustProfile;
      try {
        final policyData = await ApiService.instance
            .getPolicy(userId)
            .timeout(const Duration(seconds: 12), onTimeout: () => <String, dynamic>{});
        policy = policyData['policy'] as Map<String, dynamic>?;
      } catch (_) {}
      
      try {
        trustProfile = await ApiService.instance
            .getTrustProfile(userId)
            .timeout(const Duration(seconds: 12), onTimeout: () => <String, dynamic>{});
      } catch (_) {}
      
      final prefs = await SharedPreferences.getInstance();
      final bioEnabled = prefs.getBool('biometric_enabled') ?? true;
      final offDuty = await StorageService.instance.isOffDuty();

      if (mounted) {
        final mock = context.read<MockDataService>();
        Map<String, dynamic>? finalPolicy;

        if (mock.worker.id.startsWith('DEMO_') && mock.hasActivePolicy) {
          finalPolicy = {
            'plan_name': mock.activePolicy.plan,
            'status': mock.activePolicy.status,
            'coverage_start': mock.activePolicy.coverageStart,
            'commitment_end': mock.activePolicy.coverageEnd,
          };
        } else {
          finalPolicy = policy;
        }

        setState(() {
          _worker = worker;
          _policy = finalPolicy;
          _trustProfile = trustProfile ?? _trustProfile; // fallback if fails completely
          _biometricEnabled = bioEnabled;
          _isOffDuty = offDuty;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildZoneRow(ThemeData theme, bool isDark) {
    final currentZone = _worker?['zone'] as String? ?? 'Not set';
    return GestureDetector(
      onTap: () => _showZonePicker(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark ? [] : [
            BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.location_on_rounded, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Work Zone', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(currentZone, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_rounded, size: 12, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('Change', style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showZonePicker() async {
    final mockSvc = Provider.of<MockDataService>(context, listen: false);
    final allZones = <String>[];
    mockSvc.autocompleteCities.forEach((city, zones) {
      for (final z in zones) { allZones.add('$z|$city'); }
    });
    allZones.sort();
    String filter = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final filtered = allZones.where((z) => z.toLowerCase().contains(filter.toLowerCase())).toList();
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text('Change Work Zone', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search zone or city...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Theme.of(ctx).colorScheme.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) => setInner(() => filter = v),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final parts = filtered[i].split('|');
                      final zoneName = parts[0];
                      final cityName = parts.length > 1 ? parts[1] : '';
                      return ListTile(
                        leading: Icon(Icons.location_on_rounded, color: Theme.of(ctx).colorScheme.primary, size: 20),
                        title: Text(zoneName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(cityName, style: const TextStyle(fontSize: 12)),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          await StorageService.instance.saveUserZone(zoneName);
                          // WorkerModel.copyWith only carries zone & issScore,
                          // so rebuild with city updated too.
                          final w = mockSvc.worker;
                          mockSvc.worker = WorkerModel(
                            id: w.id, name: w.name, platform: w.platform,
                            city: cityName, zone: zoneName,
                            weeklyIncomeEstimate: w.weeklyIncomeEstimate,
                            issScore: w.issScore,
                          );
                          mockSvc.notifyListeners();
                          if (mounted) setState(() => _worker = {...?_worker, 'zone': zoneName, 'city': cityName});
                          AppEvents.instance.profileUpdated();

                          // Persist change to the backend database
                          var zoneSynced = false;
                          if (w.id.isNotEmpty) {
                            zoneSynced = await ApiService.instance.updateWorkerZone(
                              w.id,
                              zoneName,
                              cityName,
                            );
                          }

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                zoneSynced
                                    ? 'Zone updated to $zoneName'
                                    : 'Zone changed locally. Backend sync pending.',
                              ),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ));
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    
    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.canvasColor,
        body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    return MobileContainer(
      child: Scaffold(
        backgroundColor: theme.canvasColor,
        body: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.arrow_back_rounded, color: theme.colorScheme.onSurface),
                            onPressed: () {
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                context.go(AppRoutes.dashboard);
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.profile_title.toUpperCase(),
                            style: theme.textTheme.displayMedium,
                          ),
                        ],
                      ),
                      // Mode Toggle
                      const _ThemeToggle(),
                    ],
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    
                    // ── User Identity ─────────────────────────────────────
                    _buildUserIdentity(_worker, theme, isDark, l10n),
                    const SizedBox(height: 32),

                    // ── Personal Info ─────────────────────────────────────
                    Text(l10n.profile_personal_info, style: theme.textTheme.labelSmall),
                    const SizedBox(height: 16),
                    _InfoCard(
                      theme: theme,
                      isDark: isDark,
                      rows: [
                        (Icons.person_rounded, l10n.profile_name, _worker?['name'] as String? ?? 'John Doe'),
                        (Icons.phone_rounded, l10n.profile_mobile, _worker?['phone'] as String? ?? '+91 98765 43210'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Zone row — tappable to change
                    _buildZoneRow(theme, isDark),
                    const SizedBox(height: 32),

                    // ── Payout Settings ──────────────────────────────────
                    Text('PAYOUT SETTINGS', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 16),
                    _PayoutSettingsCard(theme: theme, isDark: isDark),
                    const SizedBox(height: 32),

                    // ── Account Info ──────────────────────────────────────
                    Text(l10n.profile_account_info, style: theme.textTheme.labelSmall),
                    const SizedBox(height: 16),
                    _InfoCard(
                      theme: theme,
                      isDark: isDark,
                      rows: [
                        (Icons.badge_rounded, l10n.profile_hustlr_id, _worker?['id']?.toString().split('-')[0].toUpperCase() ?? 'HUSTLR-XXXX'),
                        (Icons.shield_rounded, l10n.profile_active_plan, _policy?['plan_tier'] != null ? '${_policy!['plan_tier'].toString().toUpperCase()} SHIELD' : 'None'),
                        (Icons.calendar_today_rounded, l10n.profile_validity, _policy != null ? 'Active' : 'N/A'),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ── Security ──────────────────────────────────────────────
                    Text('SECURITY', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: isDark ? [] : [
                          BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 10))
                        ],
                      ),
                      child: FutureBuilder<bool>(
                        future: BiometricService.instance.isAvailable(),
                        builder: (context, snap) {
                          if (!(snap.data ?? false)) return const SizedBox.shrink();
                          return SwitchListTile(
                            title: const Text('Fingerprint Lock', style: TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('Require biometrics on app open', style: TextStyle(fontSize: 12)),
                            value: _biometricEnabled,
                            activeThumbColor: const Color(0xFF2E7D32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            onChanged: (val) async {
                              if (val) {
                                final result = await BiometricService.instance.authenticate(
                                  reason: 'Enable fingerprint lock for Hustlr');
                                if (!result.success) return;
                              }
                              setState(() => _biometricEnabled = val);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('biometric_enabled', val);
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Duty Mode ────────────────────────────────────────
                    Text('DUTY MODE', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: isDark
                            ? []
                            : [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.04),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                      ),
                      child: SwitchListTile(
                        title: const Text('Off Duty', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          _isOffDuty
                              ? 'Background tracking is paused. Turn this off to resume location protection.'
                              : 'Location and heartbeat are active while on duty.',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: _isOffDuty,
                        activeThumbColor: const Color(0xFF2E7D32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        onChanged: (val) => _toggleOffDuty(val),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Language Switcher ───────────────────────────────────────
                    Container(
                      margin: const EdgeInsets.only(bottom: 32),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: isDark ? [] : [
                          BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 10))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 3, height: 18,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                l10n.profile_language.toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5)
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const LanguageSwitcher(showLabel: false),
                        ],
                      ),
                    ),

                    // ── API Status ────────────────────────────────────────
                    _ApiStatusTile(theme: theme, isDark: isDark),
                    const SizedBox(height: 16),
                    
                    // ── Developer Options ─────────────────────────────────
                    GestureDetector(
                      onTap: () => context.push(AppRoutes.mlTester),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1B5E20).withValues(alpha: 0.2) : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF3FFF8B).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.code_rounded, color: Color(0xFF3FFF8B), size: 24),
                            const SizedBox(width: 16),
                            const Expanded(child: Text("Developer: ML Tester", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3FFF8B)))),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF3FFF8B)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(height: 24),
                    _buildDemoControls(context, theme, isDark),
                    const SizedBox(height: 24),

                    // ── Logout ────────────────────────────────────────────
                    Align(
                      alignment: Alignment.centerRight, // Asymmetric CTA alignment
                      child: GestureDetector(
                        onTap: () async {
                          await AuthService.logout();
                          if (context.mounted) {
                            context.read<MockDataService>().resetDemo();
                            context.go(AppRoutes.login);
                          }
                        },
                        child: Container(
                          width: 200,
                          height: 56,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1c1f1c) : const Color(0xFFFFF0F0),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                            boxShadow: isDark ? [] : [
                              BoxShadow(color: Colors.redAccent.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 8)),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                              const SizedBox(width: 8),
                              Text(l10n.profile_logout, style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.redAccent, fontWeight: FontWeight.bold
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserIdentity(Map<String, dynamic>? worker, ThemeData theme, bool isDark, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: isDark ? [] : [
          BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Text(
              worker?['name']?.substring(0, 1) ?? 'U',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            worker?['name'] ?? 'User',
            style: theme.textTheme.displaySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildDemoControls(BuildContext context, ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const DemoControlsSheet(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1c1f1c) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3FFF8B).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bug_report_rounded, color: Color(0xFF3FFF8B), size: 24),
            const SizedBox(width: 16),
            const Expanded(child: Text("HUSTLR INTERNAL CONTROLS", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3FFF8B)))),
            const Icon(Icons.keyboard_arrow_up_rounded, color: Color(0xFF3FFF8B)),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleOffDuty(bool offDuty) async {
    setState(() => _isOffDuty = offDuty);
    await StorageService.instance.setOffDuty(offDuty);

    if (offDuty) {
      await ShiftTrackingService.instance.stopShift();
      await LocationService.instance.stopTracking();
      ApiHealthService.instance.stopAutoRefresh();
      await BackgroundHeartbeatService.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Off Duty enabled. Background tracking paused.')),
      );
      return;
    }

    ApiHealthService.instance.startAutoRefresh();
    await BackgroundHeartbeatService.initialize();

    final zone = await StorageService.instance.getShiftZone() ??
        (_worker?['zone'] as String?) ??
        'Local Zone';
    await ShiftTrackingService.instance.startShift(zone);

    if (!mounted) return;
    final resumed = ShiftTrackingService.instance.status == ShiftStatus.active;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resumed
              ? 'On Duty enabled. Tracking resumed.'
              : 'On Duty enabled, but location permission/service is required to resume tracking.',
        ),
      ),
    );
  }


}

// ── Theme Toggle Switch ──────────────────────────────────────────────────────
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    ThemeProvider? themeProvider;
    try {
      themeProvider = Provider.of<ThemeProvider>(context);
    } catch (_) {
      themeProvider = null;
    }
    final theme = Theme.of(context);
    final isDark =
        themeProvider?.isDarkMode(context) ??
        (MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    // Pill switch with sun/moon
    return GestureDetector(
      onTap: () {
        if (themeProvider != null) {
          themeProvider.toggleTheme(!isDark);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.fastOutSlowIn,
        width: 64,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: isDark ? theme.colorScheme.surface : theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.4 : 0.2),
            width: 1,
          ),
          boxShadow: isDark ? [
             BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.1), blurRadius: 12)
          ] : [],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              left: isDark ? 28 : 0,
              right: isDark ? 0 : 28,
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                  boxShadow: [
                    BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.5), blurRadius: 8)
                  ],
                ),
                child: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  size: 16,
                  color: isDark ? theme.canvasColor : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _PayoutSettingsCard extends StatefulWidget {
  final ThemeData theme;
  final bool isDark;

  const _PayoutSettingsCard({required this.theme, required this.isDark});

  @override
  State<_PayoutSettingsCard> createState() => _PayoutSettingsCardState();
}

class _PayoutSettingsCardState extends State<_PayoutSettingsCard> {
  late String _upiId;

  @override
  void initState() {
    super.initState();
    _upiId = StorageService.upiId;
  }

  Future<void> _editUpi() async {
    final controller = TextEditingController(
      text: _upiId == 'add-upi-id@ybl' ? '' : _upiId,
    );
    final green = widget.isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        title: const Text('Edit UPI ID', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'example@upi',
            border: const OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: green)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty || !value.contains('@')) return;
              await StorageService.setUpiId(value);
              if (!mounted) return;
              setState(() => _upiId = value);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: green, foregroundColor: widget.isDark ? Colors.black : Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final green = widget.isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final primary = widget.isDark ? Colors.white : const Color(0xFF0D1B0F);
    final grey = widget.isDark ? const Color(0xFF91938D) : const Color(0xFF607D8B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: widget.isDark
            ? []
            : [
                BoxShadow(
                  color: widget.theme.colorScheme.primary.withValues(alpha: 0.04),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.account_balance_wallet_rounded, color: green, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Linked UPI ID', style: TextStyle(fontSize: 12, color: grey)),
                const SizedBox(height: 4),
                Text(_upiId, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
              ],
            ),
          ),
          TextButton(
            onPressed: _editUpi,
            style: TextButton.styleFrom(foregroundColor: green),
            child: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── Reusable Info Card ───────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final ThemeData theme;
  final bool isDark;
  final List<(IconData, String, String)> rows;

  const _InfoCard({required this.theme, required this.isDark, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: isDark ? [] : [
            BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 10))
          ],
        ),
        child: Column(
          children: rows.asMap().entries.map((entry) {
            final idx = entry.key;
            final row = entry.value;
            final isLast = idx == rows.length - 1;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(row.$1, color: theme.colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row.$2, style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5)
                            )),
                            const SizedBox(height: 4),
                            Text(row.$3, style: theme.textTheme.bodyLarge),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Container(
                    height: 1, 
                    margin: const EdgeInsets.only(left: 80, right: 24), 
                    color: isDark ? theme.colorScheme.surface : theme.colorScheme.surface,
                    // Use surface color as divider to match "no 1px solid dividers" rule 
                    // Tonal background shift creates the line implicitly in Dark Mode
                  )
              ],
            );
          }).toList(),
        ),
      );
  }
}

// ── API Status Tile ──────────────────────────────────────────────────────────
class _ApiStatusTile extends StatelessWidget {
  final ThemeData theme;
  final bool isDark;
  const _ApiStatusTile({required this.theme, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ApiHealthService.instance,
      builder: (context, _) {
        final status = ApiHealthService.instance.overallStatus;
        final isChecking = ApiHealthService.instance.isChecking;

        final (dotColor, label) = switch (status) {
          ApiStatus.online   => (const Color(0xFF3FFF8B), 'All APIs Online'),
          ApiStatus.degraded => (const Color(0xFFFFD54F), 'Partial Degradation'),
          ApiStatus.offline  => (const Color(0xFFFF5252), 'APIs Offline'),
          ApiStatus.unknown  => (const Color(0xFF91938d), 'Checking...'),
        };

        return GestureDetector(
          onTap: () => context.push(AppRoutes.apiStatus),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isDark ? [] : [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: dotColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isChecking
                      ? Center(
                          child: SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: dotColor,
                            ),
                          ),
                        )
                      : Icon(Icons.wifi_tethering_rounded, color: dotColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'API Status',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 7, height: 7,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotColor,
                              boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.5), blurRadius: 4)],
                            ),
                          ),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              color: dotColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
