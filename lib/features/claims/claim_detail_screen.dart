import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/mock_data_service.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/pdf_generator.dart';
import 'widgets/audit_receipt_badge.dart';

class ClaimDetailScreen extends StatefulWidget {
  final String claimId;
  final Map<String, dynamic>? initialClaim;

  const ClaimDetailScreen({
    super.key,
    required this.claimId,
    this.initialClaim,
  });

  @override
  State<ClaimDetailScreen> createState() => _ClaimDetailScreenState();
}

class _ClaimDetailScreenState extends State<ClaimDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _claim;
  String? _error;

  bool _idMatches(dynamic rawId) {
    final id = rawId?.toString() ?? '';
    final target = widget.claimId.trim();
    if (id.isEmpty || target.isEmpty) return false;
    return id == target || id.toLowerCase() == target.toLowerCase();
  }

  Map<String, dynamic>? _claimFromMock(MockDataService mock) {
    final userId = StorageService.userId;
    final isDemoSession =
        userId.startsWith('DEMO_') ||
        userId.startsWith('demo-') ||
        userId.startsWith('mock-') ||
        StorageService.getString('isDemoSession') == 'true';

    if (!isDemoSession || mock.claims.isEmpty) return null;

    final mapped = mock.claims.map((c) => <String, dynamic>{
          'id': c.id,
          'trigger_type': c.icon == 'rain'
              ? 'rain_heavy'
              : (c.icon == 'heat' ? 'heat_severe' : 'platform_outage'),
          'display_name': c.type,
          'status': c.status,
          'created_at': c.date == 'Just now'
              ? DateTime.now().toIso8601String()
              : c.date,
          'gross_payout': c.grossAmount ?? c.amount,
          'tranche1_amount': c.immediateAmount,
          'tranche2_amount': c.heldAmount,
          'zone': c.zone,
          'fps_score': c.frsScore,
        }).toList();

    for (final c in mapped) {
      if (_idMatches(c['id'])) return c;
    }
    return mapped.isNotEmpty ? mapped.first : null;
  }

  Map<String, dynamic>? _claimFromApiList(List<Map<String, dynamic>> list) {
    for (final c in list) {
      if (_idMatches(c['id'])) return c;
    }
    return list.isNotEmpty ? list.first : null;
  }

  @override
  void initState() {
    super.initState();
    _loadClaim();
  }

  Future<void> _loadClaim() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Use route payload first when available (most accurate source).
      if (widget.initialClaim != null && widget.initialClaim!.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _claim = Map<String, dynamic>.from(widget.initialClaim!);
          _loading = false;
        });
        return;
      }

      // Keep source priority aligned with Claims screen: mock/demo first.
      final mock = Provider.of<MockDataService>(context, listen: false);
      final mockClaim = _claimFromMock(mock);
      if (mockClaim != null) {
        if (!mounted) return;
        setState(() {
          _claim = mockClaim;
          _loading = false;
        });
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
      
      final data = await ApiService.instance.getClaims(effectiveUserId);
      final raw = data['claims'];
      final list = raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      final claim = _claimFromApiList(list);
      
      if (!mounted) return;
      setState(() { 
        _claim = claim; 
        if (claim == null && list.isEmpty) {
          _error = 'No claims found. Start by reporting a disruption.';
        }
        _loading = false; 
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Error loading claim: ${e.toString()}'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Theme.of(context).canvasColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _claim == null) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final primary = isDark ? Colors.white : const Color(0xFF0D1B0F);
      final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
      
      return Scaffold(
        backgroundColor: Theme.of(context).canvasColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 64, color: green),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Claim not found', 
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _loadClaim, 
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: isDark ? Colors.black : Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => context.go(AppRoutes.claims), 
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Claims'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFF1c1f1c) : const Color(0xFFE8F5E9),
                        foregroundColor: green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final claim = _claim!;
    final triggerType = (claim['trigger_type'] as String? ?? '').toLowerCase();
    final status = (claim['status'] as String? ?? 'PENDING').toUpperCase();
    final displayName = claim['display_name'] as String? ?? _triggerLabel(triggerType);
    final rawDate = claim['created_at'] as String? ?? '';
    String dateStr = rawDate;
    if (rawDate.contains('T') && rawDate.length >= 10) {
      dateStr = rawDate.substring(0, 10);
    }
    final grossPayout = (claim['gross_payout'] as num?)?.toInt() ?? 0;
    final tranche1 = (claim['tranche1_amount'] as num?)?.toInt() ?? (grossPayout * 0.7).toInt();
    final tranche2 = (claim['tranche2_amount'] as num?)?.toInt() ?? (grossPayout * 0.3).toInt();
    final fpsScore = (claim['fps_score'] as num?)?.toInt();
    final claimId = claim['id']?.toString() ?? '';

    final theme  = Theme.of(context);
    final isDark  = theme.brightness == Brightness.dark;

    final bool isApproved = status == 'APPROVED';
    final bool isPending  = status == 'PENDING' || status == 'PROCESSING';
    final bool isDeclined = status == 'DECLINED' || status == 'REJECTED';

    Color statusColor = Colors.orange;
    if (isApproved) statusColor = theme.colorScheme.primary;
    if (isDeclined) statusColor = Colors.redAccent;

    IconData triggerIcon = Icons.water_drop_rounded;
    if (triggerType.contains('heat') || triggerType.contains('temp')) triggerIcon = Icons.thermostat_rounded;
    if (triggerType.contains('downtime') || triggerType.contains('platform') || triggerType.contains('app')) triggerIcon = Icons.cloud_off_rounded;
    if (triggerType.contains('aqi') || triggerType.contains('poll')) triggerIcon = Icons.air_rounded;
    if (triggerType.contains('manual')) triggerIcon = Icons.edit_document;

    return Scaffold(
      backgroundColor: theme.canvasColor,
      appBar: AppBar(
        title: Text('Claim Details', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: theme.colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Header
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(24)),
              child: Icon(triggerIcon, size: 36, color: statusColor),
            ),
            const SizedBox(height: 20),
            Text(displayName, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text(dateStr, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: statusColor.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Text(
                status,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5),
              ),
            ),
            if (isDeclined) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => context.push(AppRoutes.autoExplanation),
                    style: TextButton.styleFrom(
                      backgroundColor: statusColor.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('See why flagged', style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, color: statusColor, size: 16),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => context.push(AppRoutes.claimAppealById(claimId), extra: claim),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: statusColor, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      elevation: 0,
                    ),
                    child: const Text('Appeal', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.5)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 40),

            // Payout Breakdown Card
            if (!isDeclined) _buildPayoutBreakdownCard(displayName, grossPayout, tranche1, tranche2, isPending, theme, isDark),

            // FRS Score card (if backend provides it)
            if (fpsScore != null) ...[
              const SizedBox(height: 32),
              _buildFraudShieldCard(fpsScore, theme, isDark),
            ],

            // ── Tamper-Evident Audit Receipt badge ───────────────────────
            AuditReceiptBadge(
              claimId:        claimId,
              receiptHash:    claim['audit_receipt_hash']    as String?,
              receiptVersion: claim['audit_receipt_version'] as String?,
              generatedAt:    claim['audit_generated_at']    as String?,
              receiptPayload: claim['audit_receipt_payload'] != null
                  ? Map<String, dynamic>.from(
                      claim['audit_receipt_payload'] as Map)
                  : null,
            ),

            const SizedBox(height: 48),
            if (isApproved)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    try {
                      final createdAt = DateTime.tryParse(rawDate) ?? DateTime.now();
                      await PdfGenerator.generateAndPreviewClaimReceipt(
                        claimId: claimId.isEmpty ? widget.claimId : claimId,
                        trigger: displayName,
                        status: status,
                        createdAt: createdAt,
                        grossPayout: grossPayout,
                        tranche1: tranche1,
                        tranche2: tranche2,
                        zone: claim['zone']?.toString(),
                        fpsScore: fpsScore,
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Could not generate receipt: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.primary, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_rounded, color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Text('Download Receipt', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  String _triggerLabel(String t) {
    if (t.contains('rain'))     return 'Rain Disruption';
    if (t.contains('heat'))     return 'Extreme Heat';
    if (t.contains('aqi'))      return 'Air Quality Alert';
    if (t.contains('downtime')) return 'Platform Downtime';
    if (t.contains('app'))      return 'Platform Outage';
    if (t.contains('manual'))   return 'Manual Report';
    return t.isNotEmpty ? t[0].toUpperCase() + t.substring(1) : 'Disruption';
  }

  Widget _buildPayoutBreakdownCard(String displayName, int grossPayout, int tranche1, int tranche2, bool isPending, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04), width: 1.5),
        boxShadow: isDark ? [] : [const BoxShadow(color: Color(0x05000000), blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 4, height: 16, color: theme.colorScheme.primary, margin: const EdgeInsets.only(right: 12)),
            Text('PAYOUT BREAKDOWN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface.withValues(alpha: 0.5), letterSpacing: 1.5)),
          ]),
          const SizedBox(height: 24),
          _buildBreakdownRow('Trigger', displayName, theme),
          _buildBreakdownRow('Gross payout', '₹$grossPayout', theme, isBold: true),
          Divider(height: 32, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
          if (isPending) ...[
            _buildBreakdownRow('Estimated payout', '₹$grossPayout', theme, isBold: true, valueColor: Colors.orange),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 8),
                Text('Settlement: Sunday 11 PM', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
              ]),
            ),
          ] else ...[
            _buildBreakdownRow('Provisional (70%)', '₹$tranche1', theme, suffixText: '[Releasing Sunday 11 PM]'),
            _buildBreakdownRow('Settlement (30%)', '₹$tranche2', theme, suffixText: '[Releasing Tuesday after 48hr review]'),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(
String label, String value, ThemeData theme, {bool isBold = false, Color? valueColor, IconData? icon, Color? iconColor, String? suffixText}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w700))),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 14, color: iconColor),
                      const SizedBox(width: 4),
                    ],
                    Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontWeight: isBold ? FontWeight.w900 : FontWeight.w700, color: valueColor ?? theme.colorScheme.onSurface, fontSize: 14))),
                  ],
                ),
                if (suffixText != null) ...[
                  const SizedBox(height: 4),
                  Text(suffixText, textAlign: TextAlign.right, style: TextStyle(color: theme.colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFraudShieldCard(int score, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Text('Hustlr Fraud Shield', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.primary, letterSpacing: -0.3)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FPS Score', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: theme.colorScheme.primary.withValues(alpha: 0.8), letterSpacing: 1.5)),
                    const SizedBox(height: 6),
                    Text('Normal Profile', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$score', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: theme.colorScheme.primary, height: 1.0)),
                  const SizedBox(width: 4),
                  Text('/ 100', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: theme.colorScheme.primary.withValues(alpha: 0.5))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
