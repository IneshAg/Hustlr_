import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../core/router/app_router.dart';
import 'package:go_router/go_router.dart';
import '../../services/app_events.dart';
import '../../services/mock_data_service.dart';
import '../../shared/widgets/mobile_container.dart';

import '../../l10n/app_localizations.dart';
import '../../services/notification_service.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  String? _error;

  int _balance = 0;
  int _totalPayouts = 0;
  int _totalPremiums = 0;
  List<Map<String, dynamic>> _transactions = [];
  Map<String, dynamic>? _cashbackStatus;
  
  StreamSubscription? _walletSub;
  StreamSubscription? _claimSub;

  @override
  void initState() {
    super.initState();
    _loadWallet();
    
    // Refresh when claims or policy events fire
    _walletSub = AppEvents.instance.onWalletUpdated.listen((_) => _loadWallet());
    _claimSub = AppEvents.instance.onClaimUpdated.listen((_) => _loadWallet());
  }

  @override
  void dispose() {
    _walletSub?.cancel();
    _claimSub?.cancel();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    final userId = await StorageService.instance.getUserId();
    if (userId == null) {
      _loadMockWallet();
      return;
    }
    
    setState(() { _loading = true; _error = null; });
    
    try {
      // Prioritize MockDataService for hackathon demo consistency
      final mock = context.read<MockDataService>();
      final isDemoUser = mock.worker.id.startsWith('DEMO_') || mock.worker.id.startsWith('demo-') || mock.worker.id.startsWith('mock-');
      
      if (isDemoUser) {
        if (!mounted) return;
        setState(() {
          _balance        = mock.walletBalance;
          _totalPayouts   = mock.monthlySavings;
          _totalPremiums  = mock.totalPremiums;
          _transactions   = List<Map<String, dynamic>>.from(mock.transactions);
          _loading        = false;
        });
        return;
      }

      final res = await ApiService.instance.getWallet(userId);
      Map<String, dynamic>? cashbackData;
      try {
        cashbackData = await ApiService.instance.getCashbackStatus(userId);
      } catch (_) {}
      
      setState(() {
        // Only use real API data - never mix with demo unless explicitly in demo mode
        final box = Hive.box('appData');
        final isDemoMode = box.get('isDemoSession', defaultValue: false) as bool;
        final mockSvc = context.read<MockDataService>();
        
        if (isDemoMode || isDemoUser) {
          // In demo mode: prioritize data from MockDataService which handles the disruption simulation
          _balance        = mockSvc.walletBalance;
          _totalPayouts   = mockSvc.monthlySavings; 
          _totalPremiums  = mockSvc.totalPremiums;
          _transactions   = List<Map<String, dynamic>>.from(mockSvc.transactions);
          
          // If mock is empty but API has data, only then use API as secondary source
          if (_balance == 0 && (res['balance'] ?? 0) > 0) {
             _balance      = res['balance'] ?? 0;
             _totalPayouts  = res['total_payouts'] ?? 0;
             _transactions  = List<Map<String, dynamic>>.from(res['transactions'] ?? []);
          }
        } else {
          // Real mode: use API data only
          _balance        = res['balance'] ?? 0;
          _totalPayouts   = res['total_payouts'] ?? 0;
          _totalPremiums  = res['total_premiums'] ?? 0;
          _transactions   = List<Map<String, dynamic>>.from(res['transactions'] ?? []);
        }
        
        _cashbackStatus = cashbackData;
        _loading        = false;
      });
      
    } catch (e) {
      print('[Wallet] API error: $e — loading mock');
      _loadMockWallet();
    }
  }

  void _loadMockWallet() {
    if (!mounted) return;
    setState(() {
      _balance       = 120;  // Match the single payout amount user expects
      _totalPayouts  = 120;
      _totalPremiums = 0;
      _loading       = false;
      _transactions  = [
        {
          'id': 'TXN_001',
          'description': 'Heavy Rain Payout (70%)',
          'amount': 120,
          'type': 'credit',
          'category': 'payout_tranche1',
          'created_at': DateTime.now().toIso8601String(),
        },
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bgScreen = isDark ? const Color(0xFF0a0b0a) : const Color(0xFFF4F6F4);
    final green    = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final red      = isDark ? const Color(0xFFFF5252) : const Color(0xFFB71C1C);
    final primary  = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final l10n     = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: bgScreen,
      appBar: AppBar(
        backgroundColor: bgScreen,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          l10n.wallet_title,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primary),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.notifications_rounded, color: primary),
                  onPressed: () async {
                    NotificationService.instance.markAllRead();
                    await context.push(AppRoutes.notifications);
                    setState(() {});
                  },
                ),
                if (NotificationService.instance.unreadCount > 0)
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(color: red, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileContainer(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorState(error: _error!, onRetry: _loadWallet)
                      : RefreshIndicator(
                          onRefresh: _loadWallet,
                          color: green,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            child: Column(
                              children: [
                                _BalanceCard(
                                  balance: _balance,
                                  totalPayouts: _totalPayouts,
                                  totalPremiums: _totalPremiums,
                                  onRefresh: _loadWallet,
                                ),
                                const SizedBox(height: 16),
                                _SavingsInsightCard(totalPayouts: _totalPayouts, totalPremiums: _totalPremiums),
                                const SizedBox(height: 16),
                                const _AnalyticsButton(),
                                const SizedBox(height: 24),
                                _WeeklySummarySection(transactions: _transactions),
                                const SizedBox(height: 24),
                                if (_cashbackStatus != null) ...[
                                  _CashbackStatusCard(status: _cashbackStatus!),
                                  const SizedBox(height: 24),
                                ],
                                _InsuranceTransactionsSection(transactions: _transactions),
                                const SizedBox(height: 24),
                                const _SupportCard(),
                              ],
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
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
    final green   = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
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
            Text('Could not load wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
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

// ─── Balance Card ─────────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final int balance;
  final int totalPayouts;
  final int totalPremiums;
  final VoidCallback onRefresh;

  const _BalanceCard({
    required this.balance,
    required this.totalPayouts,
    required this.totalPremiums,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final displayBalance = balance < 0 ? 0 : balance;
    final formattedBalance = '₹${displayBalance.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1B4332), const Color(0xFF0D2B1D)]
              : [const Color(0xFF2E7D32), const Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1B5E20))
                .withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(l10n.wallet_balance,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ]),
                GestureDetector(
                  onTap: onRefresh,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(formattedBalance,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    height: 1.0)),
            const SizedBox(height: 4),
            Text('Available to withdraw',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 12)),
            const SizedBox(height: 20),
            // ── Stats row ──────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TOTAL EARNED',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text('₹$totalPayouts',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Container(
                      width: 1,
                      height: 36,
                      color: Colors.white.withValues(alpha: 0.2)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PREMIUMS PAID',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)),
                          const SizedBox(height: 4),
                          Text('₹$totalPremiums',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => _showWithdrawBottomSheet(context, balance),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: green,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.wallet_withdraw,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: green)),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_upward_rounded, size: 16, color: green),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Savings Insight ──────────────────────────────────────────────────────────
class _SavingsInsightCard extends StatelessWidget {
  final int totalPayouts;
  final int totalPremiums;

  const _SavingsInsightCard({required this.totalPayouts, required this.totalPremiums});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final cardWhite = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final grey = isDark ? const Color(0xFF91938d) : const Color(0xFF8FAE8B);
    
    final netSavings = totalPayouts - totalPremiums;
    final formattedSavings = '₹${netSavings.abs().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}';

    return Container(
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              right: -20, top: -20,
              child: Icon(Icons.savings_rounded, size: 100, color: green.withValues(alpha: 0.05)),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.auto_graph_rounded, color: green, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.wallet_smart_savings.toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: grey, letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${l10n.wallet_you_saved} ',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: primary.withValues(alpha: 0.7)),
                            ),
                            Text(
                              formattedSavings,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: green),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Analytics Navigation ─────────────────────────────────────────────────────
class _AnalyticsButton extends StatelessWidget {
  const _AnalyticsButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final cardBg = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final borderColor = isDark ? green.withValues(alpha: 0.3) : const Color(0xFF2D6A2D).withValues(alpha: 0.3);
    final iconColor = isDark ? green : const Color(0xFF2D6A2D);

    return GestureDetector(
      onTap: () => context.push(AppRoutes.analytics),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(Icons.bar_chart, color: iconColor),
              const SizedBox(width: 8),
              Text(l10n.wallet_see_analytics, style: TextStyle(color: iconColor, fontWeight: FontWeight.w600)),
            ]),
            Icon(Icons.chevron_right, color: iconColor),
          ],
        ),
      ),
    );
  }
}

String _extractClaimReason(Map<String, dynamic> tx) {
  final metadata = tx['metadata'];
  final meta = metadata is Map ? metadata : const {};

  String pick(dynamic v) => (v?.toString() ?? '').trim();

  final candidates = [
    pick(tx['trigger_type']),
    pick(tx['display_name']),
    pick(tx['claim_reason']),
    pick(tx['reason']),
    pick(tx['trigger']),
    pick(meta['trigger_type']),
    pick(meta['display_name']),
    pick(meta['claim_reason']),
    pick(meta['reason']),
    pick(meta['trigger']),
  ];

  for (final c in candidates) {
    if (c.isNotEmpty) return c;
  }

  final category = pick(tx['category']).toLowerCase();
  if (category.contains('rain')) return 'rain_heavy';
  if (category.contains('heat')) return 'extreme_heat';
  if (category.contains('aqi') || category.contains('pollution')) return 'aqi_severe';
  if (category.contains('downtime')) return 'platform_downtime';
  if (category.contains('bandh') || category.contains('curfew')) return 'bandh';
  if (category.contains('cyclone')) return 'cyclone';
  if (category.contains('blackout') || category.contains('internet')) return 'internet_blackout';
  if (category.contains('accident')) return 'accident_blockspot';
  if (category.contains('traffic')) return 'traffic_congestion';

  return '';
}

String _formatClaimReason(String reason) {
  if (reason.trim().isEmpty) return '';

  final normalized = reason
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  const remap = {
    'rain heavy': 'Heavy Rain',
    'extreme heat': 'Extreme Heat',
    'heat severe': 'Extreme Heat',
    'aqi severe': 'Air Quality Alert',
    'aqi hazardous': 'Air Quality Alert',
    'platform downtime': 'Platform Downtime',
    'platform outage': 'Platform Downtime',
    'bandh': 'Bandh / Curfew',
    'curfew': 'Bandh / Curfew',
    'internet blackout': 'Internet Blackout',
    'dark store closure': 'Dark Store Closure',
    'accident blockspot': 'Accident Blockspot',
    'traffic congestion': 'Traffic Congestion',
  };

  if (remap.containsKey(normalized)) return remap[normalized]!;

  return normalized
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

String _buildTxTitle(Map<String, dynamic> tx, bool isCredit) {
  final description = (tx['description']?.toString() ?? '').trim();
  final category = (tx['category']?.toString() ?? '').toLowerCase();
  final reason = _formatClaimReason(_extractClaimReason(tx));

  final genericDesc = description.isEmpty ||
      description.toLowerCase() == 'transaction' ||
      description.toLowerCase() == 'wallet transfer';

  final looksLikePayout = category.contains('payout') ||
      category.contains('claim') ||
      category.contains('tranche') ||
      (isCredit && reason.isNotEmpty);

  if (looksLikePayout) {
    return reason.isNotEmpty ? '$reason Payout' : 'Claim Payout';
  }

  if (category.contains('premium') || category.contains('policy')) {
    return 'Premium Payment';
  }

  if (!genericDesc) return description;
  return 'Wallet Transfer';
}

String _buildTxSubtitle(Map<String, dynamic> tx) {
  final rawDate = tx['created_at'] as String? ?? tx['date'] as String? ?? '';

  String dateStr;
  String timeStr = '';
  if (rawDate.isNotEmpty) {
    final dt = DateTime.tryParse(rawDate);
    if (dt != null) {
      dateStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else {
      dateStr = rawDate;
      if (rawDate.contains('T') && rawDate.length >= 10) {
        dateStr = rawDate.substring(0, 10);
      }
    }
  } else {
    dateStr = 'Today';
  }

  final formattedReason = _formatClaimReason(_extractClaimReason(tx));

  var subtitle = dateStr;
  if (timeStr.isNotEmpty) subtitle += ' · $timeStr';
  if (formattedReason.isNotEmpty) subtitle += ' • $formattedReason';
  return subtitle;
}

// ─── Weekly Summary ───────────────────────────────────────────────────────────
class _WeeklySummarySection extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  const _WeeklySummarySection({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final lightGreen = isDark ? const Color(0xFF003D2A) : const Color(0xFFE8F5E9);
    final lightRed = isDark ? const Color(0xFF4A0000) : const Color(0xFFFFEBEE);
    final red = isDark ? const Color(0xFFFF6B6B) : const Color(0xFFB71C1C);
    final cardWhite = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final grey = isDark ? const Color(0xFF91938d) : const Color(0xFF8FAE8B);

    final recentTx = transactions.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _BarIcon(color: green),
            const SizedBox(width: 8),
            Text(
              l10n.wallet_recent_activity,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (recentTx.isEmpty)
          Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No recent activity', style: TextStyle(color: grey, fontSize: 14)),
          ))
        else
          ...recentTx.map((tx) {
            final rawAmount = (tx['amount'] as num?)?.toInt() ?? 0;
            final isCredit = tx['type'] == 'credit' || (tx['type'] == null && rawAmount > 0);

            final title = _buildTxTitle(tx, isCredit);
            final subtitle = _buildTxSubtitle(tx);
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildCard(
                icon: isCredit ? Icons.account_balance_wallet_rounded : Icons.shield_rounded,
                iconBg: isCredit ? lightGreen : lightRed,
                iconColor: isCredit ? green : red,
                title: title,
                date: subtitle,
                amount: isCredit ? '+₹${rawAmount.abs()}' : '−₹${rawAmount.abs()}',
                amountColor: isCredit ? green : red,
                cardBg: cardWhite,
                primary: primary,
                grey: grey,
              ),
            );
          }),
      ],
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String date,
    required String amount,
    required Color amountColor,
    required Color cardBg,
    required Color primary,
    required Color grey,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
                const SizedBox(height: 2),
                Text(date, style: TextStyle(fontSize: 12, color: grey)),
              ],
            ),
          ),
          Text(amount, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: amountColor)),
        ],
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  final Color color;
  const _BarIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _bar(10, color), const SizedBox(width: 2),
          _bar(16, color), const SizedBox(width: 2),
          _bar(8,  color), const SizedBox(width: 2),
          _bar(12, color),
        ],
      ),
    );
  }

  Widget _bar(double height, Color color) => Container(
    width: 3, height: height,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
  );
}

// ─── Insurance Transactions ───────────────────────────────────────────────────
class _InsuranceTransactionsSection extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  const _InsuranceTransactionsSection({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final red = isDark ? const Color(0xFFFF6B6B) : const Color(0xFFB71C1C);
    final cardWhite = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final grey = isDark ? const Color(0xFF91938d) : const Color(0xFF8FAE8B);
    final divider = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF3F4F6);
    final lightBlue = isDark ? const Color(0xFF003D2A) : const Color(0xFFF0FDF4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(Icons.history_rounded, size: 18, color: green),
              const SizedBox(width: 8),
              Text(
                l10n.wallet_recent_transactions,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary),
              ),
            ]),
            TextButton(
              onPressed: () => context.push(AppRoutes.analytics),
              child: Text(
                l10n.wallet_see_all,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: green),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: divider),
            ),
            child: Column(
              children: [
                Icon(Icons.receipt_long_rounded, color: grey.withValues(alpha: 0.3), size: 48),
                const SizedBox(height: 12),
                Text('No transactions yet', style: TextStyle(color: grey, fontSize: 14)),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: divider),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: transactions.length,
              separatorBuilder: (_, __) => Divider(color: divider, height: 1, indent: 70, endIndent: 20),
              itemBuilder: (context, index) {
                final tx = transactions[index];
                final rawAmount = (tx['amount'] as num?)?.toInt() ?? 0;
                final isCredit = tx['type'] == 'credit' || (tx['type'] == null && rawAmount > 0);

                final title = _buildTxTitle(tx, isCredit);
                final subtitle = _buildTxSubtitle(tx);
                
                return _buildTransactionRow(
                  icon: isCredit ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                  iconColor: isCredit ? green : red,
                  iconBg: isCredit ? lightBlue : red.withValues(alpha: 0.05),
                  title: title,
                  subtitle: subtitle,
                  amount: isCredit ? '+₹${rawAmount.abs()}' : '−₹${rawAmount.abs()}',
                  amountColor: isCredit ? green : red,
                  primary: primary,
                  grey: grey,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTransactionRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String amount,
    required Color amountColor,
    required Color primary,
    required Color grey,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 12, color: grey)),
              ],
            ),
          ),
          Text(amount, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: amountColor)),
        ],
      ),
    );
  }
}

// ─── Support Card ─────────────────────────────────────────────────────────────
class _SupportCard extends StatelessWidget {
  const _SupportCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final cardWhite = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF0D1B0F);

    return GestureDetector(
      onTap: () => context.push(AppRoutes.support),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.wallet_help_title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
              const SizedBox(height: 2),
              Row(children: [
                Text(l10n.wallet_chat, style: TextStyle(fontSize: 13, color: green, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 14, color: green),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── UPI Withdrawal Flow ──────────────────────────────────────────────────────
void _showWithdrawBottomSheet(BuildContext context, int balance) {
  if (balance <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No balance available to withdraw')),
    );
    return;
  }

  final savedUpi    = StorageService.upiId;
  final hasLinkedUpi = savedUpi.trim().isNotEmpty && savedUpi != 'add-upi-id@ybl';
  final displayUpi  = savedUpi == 'add-upi-id@ybl' ? 'Not set — update in Profile' : savedUpi;
  final isDark      = Theme.of(context).brightness == Brightness.dark;
  final sheetBg     = isDark ? const Color(0xFF1C1F1C) : Colors.white;
  final inputBg     = isDark ? const Color(0xFF0A0B0A) : const Color(0xFFF4F6F4);
  final green       = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
  final lightGreen  = isDark ? const Color(0xFF004734) : const Color(0xFFE8F5E9);
  final primary     = isDark ? Colors.white : const Color(0xFF0D1B0F);
  final grey        = isDark ? const Color(0xFF91938D) : const Color(0xFF8FAE8B);
  final divider     = isDark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFE5E7EB);
  final btnTxt      = isDark ? const Color(0xFF0A0B0A) : Colors.white;

  final parentContext = context;
  bool bankDirect  = false;
  int selectedAmt  = balance;
  final chip25     = (balance * 0.25).round().clamp(1, balance);
  final chip50     = (balance * 0.5).round().clamp(1, balance);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: sheetBg,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetCtx) {
      return StatefulBuilder(builder: (ctx, setSS) {
        // ── Amount chip builder ──────────────────────────────────────────
        Widget chip(String label, int val) {
          final sel = selectedAmt == val;
          return Expanded(
            child: GestureDetector(
              onTap: () => setSS(() => selectedAmt = val),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: sel ? green : inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: sel ? green : divider, width: 1.5),
                ),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: sel ? btnTxt : primary)),
              ),
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──────────────────────────────────────────
                    Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                            color: lightGreen, shape: BoxShape.circle),
                        child: Icon(Icons.arrow_upward_rounded,
                            color: green, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Withdraw Funds',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: primary)),
                          Text('Available: ₹$balance',
                              style: TextStyle(fontSize: 13, color: grey)),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // ── Amount chips ─────────────────────────────────────
                    Text('SELECT AMOUNT',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: grey,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 10),
                    Row(children: [
                      chip('₹$chip25', chip25),
                      const SizedBox(width: 8),
                      chip('₹$chip50', chip50),
                      const SizedBox(width: 8),
                      chip('Full  ₹$balance', balance),
                    ]),
                    const SizedBox(height: 12),

                    // ── Method toggle ────────────────────────────────────
                    Text('TRANSFER TO',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: grey,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                          color: inputBg,
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.all(4),
                      child: Row(children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setSS(() => bankDirect = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: !bankDirect ? green : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.account_balance_wallet_rounded,
                                      size: 15,
                                      color: !bankDirect ? btnTxt : grey),
                                  const SizedBox(width: 6),
                                  Text('UPI / Wallet',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: !bankDirect ? btnTxt : grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setSS(() => bankDirect = true),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: bankDirect ? green : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.account_balance_rounded,
                                      size: 15,
                                      color: bankDirect ? btnTxt : grey),
                                  const SizedBox(width: 6),
                                  Text('Bank Direct',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: bankDirect ? btnTxt : grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // ── Destination card ─────────────────────────────────
                    if (!bankDirect) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: hasLinkedUpi ? lightGreen : inputBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: hasLinkedUpi
                                  ? green.withValues(alpha: 0.4)
                                  : divider),
                        ),
                        child: Row(children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: hasLinkedUpi
                                  ? green.withValues(alpha: 0.15)
                                  : divider,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.account_balance_wallet_rounded,
                                color: hasLinkedUpi ? green : grey, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Linked UPI',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: grey,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(displayUpi,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: hasLinkedUpi ? primary : grey)),
                              ],
                            ),
                          ),
                          if (!hasLinkedUpi)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('Set in Profile',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: green,
                                      fontWeight: FontWeight.bold)),
                            ),
                        ]),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: lightGreen,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: green.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          Icon(Icons.account_balance_rounded,
                              color: green, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Transfers directly to your bank account'
                              ' linked with your registered phone number.',
                              style: TextStyle(
                                  fontSize: 12, color: green, height: 1.5),
                            ),
                          ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // ── ETA pill ─────────────────────────────────────────
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: inputBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: divider),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.schedule_rounded,
                              size: 14, color: grey),
                          const SizedBox(width: 6),
                          Text(
                            bankDirect
                                ? 'Arrives in 1–2 business days'
                                : 'Arrives instantly via UPI',
                            style: TextStyle(
                                fontSize: 12,
                                color: grey,
                                fontWeight: FontWeight.w500),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── CTA ──────────────────────────────────────────────
                    SizedBox(
                      width: double.infinity, height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          if (!bankDirect && !hasLinkedUpi) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Please set your UPI ID in Profile first.')),
                            );
                            return;
                          }
                          final upi = bankDirect ? '' : displayUpi;
                          Navigator.pop(sheetCtx);
                          _processWithdrawal(parentContext, selectedAmt, upi,
                              bankDirect: bankDirect);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: btnTxt,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_upward_rounded,
                                size: 18, color: btnTxt),
                            const SizedBox(width: 8),
                            Text(
                              bankDirect
                                  ? 'Transfer ₹$selectedAmt to Bank'
                                  : 'Withdraw ₹$selectedAmt',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: btnTxt),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      });
    },
  );
}




void _processWithdrawal(BuildContext context, int amount, String upiId, {bool bankDirect = false}) async {
  final isDark    = Theme.of(context).brightness == Brightness.dark;
  final green     = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2D6A2D);
  final primary   = isDark ? const Color(0xFFE1E3DE) : const Color(0xFF0D1B0F);
  final grey      = isDark ? const Color(0xFF91938D) : Colors.grey;
  final successBg = isDark ? const Color(0xFF0A0B0A) : Colors.white;
  final btnTxt    = isDark ? const Color(0xFF0A0B0A) : Colors.white;

  bool cancelled = false;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      // After 8s show a cancel button
      Future.delayed(const Duration(seconds: 8), () {
        if (!cancelled && dialogCtx.mounted) {
          (dialogCtx as Element).markNeedsBuild();
        }
      });
      return StatefulBuilder(builder: (ctx, setDialogState) {
        return Dialog(
          backgroundColor: successBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(green)),
                const SizedBox(height: 24),
                Text('Initiating transfer...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary)),
                const SizedBox(height: 8),
                Text(bankDirect ? 'Connecting to bank account' : 'Connecting to UPI network', style: TextStyle(fontSize: 14, color: grey)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    cancelled = true;
                    Navigator.of(ctx, rootNavigator: true).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Transfer cancelled.')),
                    );
                  },
                  child: Text('Cancel', style: TextStyle(color: grey, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      });
    },
  );

  try {
    final userId = await StorageService.instance.getUserId();
    if (userId == null) throw Exception('User not logged in');

    // ── Demo Withdrawal Guard ───────────────────────────────────────────────
    final mock = Provider.of<MockDataService>(context, listen: false);
    Map<String, dynamic> result;

    if (mock.worker.id.startsWith('DEMO_')) {
      // Fake network latency
      await Future.delayed(const Duration(seconds: 2));
      result = {
        'status': 'success',
        'transaction_id': 'HS-DEMO-${DateTime.now().millisecondsSinceEpoch % 100000}',
      };
    } else {
      // Call real API with 15s timeout
      result = await ApiService.instance.withdrawToBank(
        userId: userId,
        amount: amount,
        upiId: bankDirect ? null : upiId,
        bankDirect: bankDirect,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('UPI network timed out. Try again.'),
      );
    }

    if (cancelled) return;
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading

    // Also update mock service so demo mode shows change
    try { context.read<MockDataService>().withdrawToUPI(amount, upiId); } catch (_) {}
    AppEvents.instance.walletUpdated();

    final formattedBalance = amount.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    final txnRef = result['transaction_id']?.toString() ??
        'TXN-HUSTLR-${DateTime.now().millisecondsSinceEpoch % 100000}';

    final dateStr = '${DateTime.now().day} ${_monthName(DateTime.now().month)} ${DateTime.now().year}, ${DateTime.now().hour > 12 ? DateTime.now().hour - 12 : (DateTime.now().hour == 0 ? 12 : DateTime.now().hour)}:${DateTime.now().minute.toString().padLeft(2, '0')} ${DateTime.now().hour >= 12 ? 'PM' : 'AM'}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (successCtx) => Dialog(
        backgroundColor: successBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Section: Green Success Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A2D),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Withdrawal Successful',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹$formattedBalance',
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                    ),
                  ],
                ),
              ),
              
              // Receipt Details Section
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  children: [
                    _buildReceiptRow('To', bankDirect ? 'Linked Bank Account' : upiId, grey, primary),
                    const SizedBox(height: 16),
                    _buildReceiptRow('Date & Time', dateStr, grey, primary),
                    const SizedBox(height: 16),
                    _buildReceiptRow('Reference No.', txnRef, grey, primary),
                    const SizedBox(height: 24),
                    
                    // Dashed Line
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Flex(
                          direction: Axis.horizontal,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.max,
                          children: List.generate(
                            (constraints.constrainWidth() / 8).floor(),
                            (index) => SizedBox(
                              width: 4, height: 1.5,
                              child: DecoratedBox(decoration: BoxDecoration(color: isDark ? const Color(0xFF2E332E) : Colors.grey[300])),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(successCtx, rootNavigator: true).pop();
                          AppEvents.instance.walletUpdated();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: btnTxt,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text('Done', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: btnTxt)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } on TimeoutException catch (e) {
    if (cancelled || !context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message ?? 'Transfer timed out. Please try again.'), backgroundColor: Colors.redAccent),
    );
  } catch (e) {
    if (cancelled || !context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    final errMsg = e.toString().replaceAll('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Transfer failed: $errMsg'), backgroundColor: Colors.redAccent),
    );
  }
}

// ─── Cashback Status ─────────────────────────────────────────────────────────
class _CashbackStatusCard extends StatelessWidget {
  final Map<String, dynamic> status;
  const _CashbackStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final cardWhite = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF0D1B0F);
    final grey = isDark ? const Color(0xFF91938d) : const Color(0xFF8FAE8B);

    final int weeks = (status['current_clean_weeks'] as num?)?.toInt() ?? 0;
    final int remaining = 13 - weeks;
    final double cashback = (status['potential_cashback'] as num?)?.toDouble() ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: green.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.stars_rounded, size: 20, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    'Claim-Free Bonus',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('₹${cashback.toInt()}',
                    style: TextStyle(color: green, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: List.generate(13, (index) {
              Color blockColor;
              if (index < weeks) {
                blockColor = green; 
              } else if (index == weeks) {
                blockColor = green.withValues(alpha: 0.3);
              } else {
                blockColor = isDark ? const Color(0xFF2E332E) : const Color(0xFFF3F4F6);
              }
              return Expanded(
                child: Container(
                  height: 8,
                  margin: EdgeInsets.only(right: index < 12 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: blockColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 13, height: 1.4, color: grey, fontFamily: 'Outfit'),
              children: [
                const TextSpan(text: 'Maintain your streak for '),
                TextSpan(text: '$remaining more weeks', style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
                const TextSpan(text: ' to unlock your bonus!'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _monthName(int month) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (month >= 1 && month <= 12) return months[month - 1];
  return '';
}

Widget _buildReceiptRow(String label, String value, Color labelColor, Color valueColor) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 14, color: labelColor, fontWeight: FontWeight.w500)),
      const SizedBox(width: 16),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 14, color: valueColor, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

