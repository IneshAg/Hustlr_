import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/app_events.dart';
import '../../services/storage_service.dart';
import '../../shared/widgets/mobile_container.dart';
import '../../shared/widgets/notification_bell.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import 'package:provider/provider.dart';
import '../../services/mock_data_service.dart';
import '../../services/connectivity_service.dart';
import '../../shared/widgets/offline_banner.dart';
import '../../shared/widgets/animated_skeleton.dart';

class ClaimsScreen extends StatefulWidget {
  const ClaimsScreen({super.key});

  @override
  State<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends State<ClaimsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _claims = [];
  StreamSubscription<void>? _claimSub;
  StreamSubscription<void>? _walletSub;
  StreamSubscription<void>? _policySub;
  StreamSubscription<void>? _connSub;
  bool _isSyncing = false;

  Future<void> _syncQueuedManualClaims(String userId) async {
    if (_isSyncing) return;
    
    final isOnline = await ConnectivityService.instance.checkNow();
    if (!isOnline) return;

    final queue = await StorageService.getPendingManualClaimsQueue();
    if (queue.isEmpty) return;

    _isSyncing = true;
    final now = DateTime.now();

    for (final item in queue) {
      if (item.nextRetryAt.isAfter(now)) {
        continue; // Backoff still active
      }
      
      // Calculate next backoff: 5s -> 15s -> 60s -> 5m max
      int nextDelaySecs = 5;
      if (item.retryCount == 1) {
        nextDelaySecs = 15;
      } else if (item.retryCount == 2) {
        nextDelaySecs = 60;
      } else if (item.retryCount >= 3) {
        nextDelaySecs = 300; // Cap at 5 mins
      }

      try {
        await ApiService.instance.submitManualClaim(
          userId: userId,
          disruptionType: item.type,
          description: item.description,
          evidenceUrls: item.evidenceUrls,
          deviceSignalStrength: item.deviceSignalStrength,
          sensorFeatures: item.sensorFeatures,
          integrityToken: item.integrityToken,
          idempotencyKey: item.localId,
        );
        // Sync successful, remove from queue
        await StorageService.removeQueuedClaim(item.localId);
      } catch (e) {
        // Sync failed, update retry metadata
        final updated = item.copyWith(
          retryCount: item.retryCount + 1,
          lastAttemptAt: now,
          nextRetryAt: now.add(Duration(seconds: nextDelaySecs)),
          lastError: e.toString(),
        );
        await StorageService.updateQueuedClaim(updated);
      }
    }
    _isSyncing = false;
  }

  @override
  void initState() {
    super.initState();
    _loadClaims();
    _claimSub = AppEvents.instance.onClaimUpdated.listen((_) => _loadClaims());
    _walletSub = AppEvents.instance.onWalletUpdated.listen((_) => _loadClaims());
    _policySub = AppEvents.instance.onPolicyUpdated.listen((_) => _loadClaims());
    _connSub = AppEvents.instance.onConnectivityRestored.listen((_) => _loadClaims());
  }

  @override
  void dispose() {
    _claimSub?.cancel();
    _walletSub?.cancel();
    _policySub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _loadClaims() async {
    setState(() { _loading = true; _error = null; });
    try {
      final mock = Provider.of<MockDataService>(context, listen: false);
      final uid = await StorageService.instance.getUserId() ?? '';
      final isDemoSession =
          uid.startsWith('DEMO_') ||
          uid.startsWith('demo-') ||
          uid.startsWith('mock-') ||
          StorageService.getString('isDemoSession') == 'true';

      if (isDemoSession && mock.claims.isNotEmpty) {
        final mockList = mock.claims.map((c) => {
          'id': c.id,
          'trigger_type': c.icon == 'rain' ? 'rain_heavy' : (c.icon == 'heat' ? 'heat_severe' : 'platform_outage'),
          'display_name': c.type,
          'status': c.status,
          'created_at': c.date == 'Just now' ? DateTime.now().toIso8601String() : c.date,
          'gross_payout': c.amount,
          'zone': c.zone,
        }).toList();
        
        if (!mounted) return;
        setState(() { _claims = mockList; _loading = false; });
        return;
      }

      final userId = await StorageService.instance.getUserId();
      final fallbackUserId = (StorageService.phone.isNotEmpty)
          ? 'local-${StorageService.phone.replaceAll(RegExp(r'\D'), '')}'
          : 'demo-local-user';
      final effectiveUserId = (userId == null || userId.trim().isEmpty)
          ? fallbackUserId
          : userId;

      if (userId == null || userId.trim().isEmpty) {
        await StorageService.setUserId(effectiveUserId);
      }

      await _syncQueuedManualClaims(effectiveUserId);

      final data = await ApiService.instance.getClaims(effectiveUserId);
      final raw = data['claims'];
      final list = raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      final pendingQueue = await StorageService.getPendingManualClaimsQueue();
      final pendingLocal = pendingQueue.map((q) {
        return <String, dynamic>{
          'id': q.localId,
          'trigger_type': q.type,
          'display_name': q.description,
          'status': 'PENDING_SYNC',
          'created_at': q.createdAt.toIso8601String(),
          'gross_payout': 0,
          'zone': '',
        };
      }).toList();

      final merged = [...pendingLocal, ...list];
      if (!mounted) return;
      setState(() { _claims = merged; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgScreen = theme.scaffoldBackgroundColor;

    // Aggregate stats from real claims
    int totalClaimed  = _claims.fold(0, (s, c) => s + ((c['gross_payout'] as num?)?.toInt() ?? 0));
    int totalReceived = _claims
        .where((c) => (c['status'] as String? ?? '').toUpperCase() == 'APPROVED')
        .fold(0, (s, c) => s + ((c['gross_payout'] as num?)?.toInt() ?? 0));
    int pendingCount = _claims
        .where((c) {
          final s = (c['status'] as String? ?? '').toUpperCase();
          return s == 'PENDING' || s == 'PENDING_SYNC' || s == 'PROCESSING';
        })
        .length;

    final blueLight  = isDark ? const Color(0xFF003D2A) : const Color(0xFFE3F2FD);
    final blue       = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1976D2);
    final tealLight  = isDark ? const Color(0xFF1C1F1C) : const Color(0xFFE8F5E9);
    final teal       = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1B5E20);
    final amberLight = isDark ? const Color(0xFF2D1B00) : const Color(0xFFFFF3E0);
    final amber      = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
    final greenText  = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1B5E20);
    final greenBg    = isDark ? const Color(0xFF004734) : const Color(0xFFE8F5E9);

    return Scaffold(
      backgroundColor: bgScreen,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileContainer(
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    const OfflineBanner(),
                    const _TopBar(),
                    Expanded(
                      child: _loading
                          ? _buildClaimsSkeleton()
                          : _error != null
                              ? _ErrorState(error: _error!, onRetry: _loadClaims)
                              : RefreshIndicator(
                                  onRefresh: _loadClaims,
                                  child: SingleChildScrollView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // ── 7-Day Waiting Period Banner ──
                                        if (context.read<MockDataService>().hasActivePolicy || _claims.any((c) => c['status'] == 'PENDING')) 
                                          FutureBuilder<Map<String, dynamic>>(
                                            future: StorageService.instance.getUserId().then((uid) => uid != null ? ApiService.instance.getPolicy(uid) : {}),
                                            builder: (context, snapshot) {
                                              if (snapshot.hasData && snapshot.data!['policy'] != null) {
                                                final policy = snapshot.data!['policy'];
                                                final createdAtStr = policy['created_at']?.toString();
                                                if (createdAtStr != null) {
                                                  final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
                                                  final daysActive = DateTime.now().difference(createdAt).inDays;
                                                  if (daysActive < 7) {
                                                    return Container(
                                                      margin: const EdgeInsets.only(bottom: 16),
                                                      padding: const EdgeInsets.all(16),
                                                      decoration: BoxDecoration(
                                                        color: Colors.orange.withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          const Icon(Icons.info_outline, color: Colors.orange, size: 24),
                                                          const SizedBox(width: 12),
                                                          const Expanded(
                                                            child: Text(
                                                              'Waiting Period: Automated payouts and manual reports will be enabled after 7 days of protection.',
                                                              style: TextStyle(fontSize: 13, color: Colors.orange, fontWeight: FontWeight.w500),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }
                                                }
                                              }
                                              return const SizedBox.shrink();
                                            },
                                          ),
                                        _SummaryRow(
                                          totalClaimed: totalClaimed,
                                          totalReceived: totalReceived,
                                          pendingCount: pendingCount,
                                        ),
                                        const SizedBox(height: 16),
                                        const _EducationBanner(),
                                        const SizedBox(height: 20),
                                        Text(
                                          'RECENT HISTORY',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: theme.colorScheme.onSurface,
                                            letterSpacing: 0.3,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        if (_claims.isEmpty)
                                          _EmptyClaimsState()
                                        else
                                          ListView.builder(
                                            shrinkWrap: true,
                                            physics: const NeverScrollableScrollPhysics(),
                                            itemCount: _claims.length,
                                            itemBuilder: (context, index) {
                                              final claim = _claims[index];
                                              final triggerType = (claim['trigger_type'] as String? ?? '').toLowerCase();
                                              final status = (claim['status'] as String? ?? 'PENDING').toUpperCase();
                                              final rawDate = claim['created_at'] as String? ?? '';
                                              String dateStr = rawDate;
                                              if (rawDate.contains('T') && rawDate.length >= 10) {
                                                dateStr = rawDate.substring(0, 10);
                                              }
                                              final amount = (claim['gross_payout'] as num?)?.toInt() ?? 0;
                                              final claimId = claim['id'] ?? '';
                                              final hasGapWarning = claim['gps_gap_flag'] == true ||
                                                  claim['frs_flags'] is List &&
                                                      (claim['frs_flags'] as List).any(
                                                        (f) => f.toString().contains('gap'),
                                                      );

                                              // Icon mapping by trigger type
                                              Color iconBg    = blueLight;
                                              IconData iconData = Icons.water_drop_rounded;
                                              Color iconColor = blue;
                                              String displayName = claim['display_name'] as String? ?? _triggerLabel(triggerType);

                                              if (triggerType.contains('heat') || triggerType.contains('temperature')) {
                                                iconBg    = amberLight;
                                                iconData  = Icons.thermostat_rounded;
                                                iconColor = amber;
                                              } else if (triggerType.contains('downtime') || triggerType.contains('platform') || triggerType.contains('app')) {
                                                iconBg    = tealLight;
                                                iconData  = Icons.cloud_off_rounded;
                                                iconColor = teal;
                                              } else if (triggerType.contains('aqi') || triggerType.contains('pollution')) {
                                                iconBg    = amberLight;
                                                iconData  = Icons.air_rounded;
                                                iconColor = amber;
                                              } else if (triggerType.contains('manual')) {
                                                iconBg    = tealLight;
                                                iconData  = Icons.edit_document;
                                                iconColor = teal;
                                              }

                                              // Badge colors
                                              Color statusBg, statusColor;
                                              if (status == 'APPROVED') {
                                                statusBg    = greenBg;
                                                statusColor = greenText;
                                              } else if (status == 'PENDING' || status == 'PROCESSING' || status == 'PENDING_SYNC') {
                                                statusBg    = amberLight;
                                                statusColor = amber;
                                              } else if (status == 'FLAGGED') {
                                                statusBg    = isDark ? const Color(0xFF3D1200) : const Color(0xFFFFF0E0);
                                                statusColor = isDark ? const Color(0xFFFF9800) : const Color(0xFFE65100);
                                              } else {
                                                // DECLINED / REJECTED
                                                statusBg    = isDark ? const Color(0xFF4A0000) : const Color(0xFFFFEBEE);
                                                statusColor = isDark ? const Color(0xFFFF6B6B) : const Color(0xFFB71C1C);
                                              }

                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 12),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    if (hasGapWarning)
                                                      Container(
                                                        margin: const EdgeInsets.only(bottom: 6),
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFFFF8E1),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(color: const Color(0xFFFFA000).withValues(alpha: 0.4)),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            const Icon(Icons.gps_not_fixed, color: Color(0xFFF57C00), size: 14),
                                                            const SizedBox(width: 8),
                                                            const Expanded(
                                                              child: Text(
                                                                'GPS signal was interrupted during this event. Claim is under manual verification.',
                                                                style: TextStyle(fontSize: 11, color: Color(0xFF7B3F00)),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    InkWell(
                                                      onTap: () => context.push(AppRoutes.claimDetailById(claimId.toString()), extra: claim),
                                                      borderRadius: BorderRadius.circular(16),
                                                      child: _ClaimCard(
                                                        iconBg: iconBg,
                                                        icon: iconData,
                                                        iconColor: iconColor,
                                                        title: displayName,
                                                        date: dateStr,
                                                        status: status == 'PENDING_SYNC' ? 'PENDING SYNC' : status,
                                                        statusBg: statusBg,
                                                        statusColor: statusColor,
                                                        amount: '₹$amount',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        const SizedBox(height: 80),
                                      ],
                                    ),
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 24,
            child: FloatingActionButton.extended(
              onPressed: () async {
                final uid = await StorageService.instance.getUserId();
                if (uid != null) {
                  final data = await ApiService.instance.getPolicy(uid);
                  final policy = data['policy'];
                  if (policy != null) {
                    final createdAtStr = policy['created_at']?.toString();
                    if (createdAtStr != null) {
                      final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
                      final daysActive = DateTime.now().difference(createdAt).inDays;
                      if (daysActive < 7) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Waiting Period: Manual reporting enabled in ${7 - daysActive} days.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                        return;
                      }
                    }
                  }
                }
                if (mounted) context.push(AppRoutes.manualEvidence);
              },
              label: const Text('Report Manually'),
              icon: const Icon(Icons.edit_document),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimsSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Row Skeleton
          const AnimatedSkeleton(height: 80, width: double.infinity, borderRadius: 12),
          const SizedBox(height: 16),
          // Education Banner Skeleton
          const AnimatedSkeleton(height: 64, width: double.infinity, borderRadius: 12),
          const SizedBox(height: 20),
          // Recent History Title Skeleton
          const AnimatedSkeleton(height: 20, width: 140, borderRadius: 6),
          const SizedBox(height: 12),
          // Claim Cards Skeleton
          const AnimatedSkeleton(height: 84, width: double.infinity, borderRadius: 16),
          const SizedBox(height: 12),
          const AnimatedSkeleton(height: 84, width: double.infinity, borderRadius: 16),
          const SizedBox(height: 12),
          const AnimatedSkeleton(height: 84, width: double.infinity, borderRadius: 16),
        ],
      ),
    );
  }

  String _triggerLabel(String triggerType) {
    if (triggerType.contains('rain'))     return 'Rain Disruption';
    if (triggerType.contains('heat'))     return 'Extreme Heat';
    if (triggerType.contains('aqi'))      return 'Air Quality Alert';
    if (triggerType.contains('internet') || triggerType.contains('blackout')) return 'Internet Blackout';
    if (triggerType.contains('downtime')) return 'Platform Downtime';
    if (triggerType.contains('app'))      return 'App Downtime';
    if (triggerType.contains('manual'))   return 'Manual Report';
    return triggerType.isNotEmpty ? triggerType[0].toUpperCase() + triggerType.substring(1) : 'Disruption';
  }
}

// ─── Error State ───────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final green   = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1B5E20);
    final primary = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final grey    = isDark ? const Color(0xFF91938d) : const Color(0xFF8FAE8B);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: grey),
            const SizedBox(height: 16),
            Text('Could not load claims', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
            const SizedBox(height: 8),
            Text(error, style: TextStyle(fontSize: 12, color: grey), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                foregroundColor: isDark ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyClaimsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green  = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1B5E20);
    final primary = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final grey   = isDark ? const Color(0xFF91938d) : const Color(0xFF8FAE8B);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.verified_outlined, size: 64, color: green),
            const SizedBox(height: 16),
            Text('No claims yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
            const SizedBox(height: 8),
            Text('Claims will appear here when disruptions are detected or you file a manual report.',
                style: TextStyle(fontSize: 13, color: grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─── Top Bar ─────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final bgColor = theme.scaffoldBackgroundColor;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Expanded(child: SizedBox()),
          Text(
            'Claims',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: const NotificationBell(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Row Card ─────────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  final int totalClaimed;
  final int totalReceived;
  final int pendingCount;

  const _SummaryRow({
    required this.totalClaimed,
    required this.totalReceived,
    required this.pendingCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    final cardBg   = theme.cardColor;
    final greenText = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1B5E20);
    final amber     = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.08),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          Expanded(child: _SummarySection(label: 'CLAIMED',  value: '₹$totalClaimed',  valueColor: theme.colorScheme.onSurface)),
          const _VerticalDivider(),
          Expanded(child: _SummarySection(
            label: 'RECEIVED', value: '₹$totalReceived', valueColor: greenText,
            trailing: Icon(Icons.check_circle, color: greenText, size: 16),
          )),
          const _VerticalDivider(),
          Expanded(child: _SummarySection(label: 'PENDING',  value: '$pendingCount',   valueColor: amber)),
        ]),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Widget? trailing;

  const _SummarySection({
    required this.label,
    required this.value,
    required this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grey   = isDark ? const Color(0xFF91938D) : const Color(0xFF8FAE8B);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: grey, letterSpacing: 1.0)),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: valueColor)),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final divColor = isDark ? const Color(0xFF2A2D2A) : const Color(0xFFE0E0E0);
    return Container(
      width: 1, height: 40, color: divColor,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ─── Education Banner ─────────────────────────────────────────────────────────
class _EducationBanner extends StatelessWidget {
  const _EducationBanner();

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bannerBg    = isDark ? const Color(0xFF003D2A) : const Color(0xFFE3F2FD);
    final accentColor = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1976D2);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bannerBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoCircle(color: accentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Hustlr auto-detects disruptions and processes claims by Sunday 11 PM for you.',
              style: TextStyle(fontSize: 13, color: accentColor, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCircle extends StatelessWidget {
  final Color color;
  const _InfoCircle({required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text('i', style: TextStyle(
          color: isDark ? const Color(0xFF0A0B0A) : Colors.white,
          fontSize: 16, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic,
        )),
      ),
    );
  }
}

// ─── Claim Card ───────────────────────────────────────────────────────────────
class _ClaimCard extends StatelessWidget {
  final Color iconBg;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String date;
  final String status;
  final Color statusBg;
  final Color statusColor;
  final String amount;

  const _ClaimCard({
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.date,
    required this.status,
    required this.statusBg,
    required this.statusColor,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final errorRed = isDark ? const Color(0xFFFF6B6B) : const Color(0xFFB71C1C);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.08),
            blurRadius: 10, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(date, style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF91938D) : const Color(0xFF8FAE8B))),
                const SizedBox(height: 8),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg, borderRadius: BorderRadius.circular(20)),
                    child: Text(status, style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: statusColor, letterSpacing: 0.8)),
                  ),
                  if (status == 'DECLINED' || status == 'REJECTED') ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => context.push(AppRoutes.autoExplanation),
                      child: Text('See why →', style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold, color: errorRed)),
                    ),
                  ],
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(amount, style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }
}
