import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A collapsible green badge shown at the bottom of a claim detail.
/// Displays a SHA-256 tamper-evident audit receipt — every trigger value,
/// fraud score, zone reading and payout was locked at approval time.
/// Any modification to the claim after approval breaks this hash.
class AuditReceiptBadge extends StatefulWidget {
  final String claimId;
  final String? receiptHash;
  final String? receiptVersion;
  final String? generatedAt;
  final Map<String, dynamic>? receiptPayload;

  const AuditReceiptBadge({
    super.key,
    required this.claimId,
    this.receiptHash,
    this.receiptVersion,
    this.generatedAt,
    this.receiptPayload,
  });

  @override
  State<AuditReceiptBadge> createState() => _AuditReceiptBadgeState();
}

class _AuditReceiptBadgeState extends State<AuditReceiptBadge>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _fadeIn;

  static const _green     = Color(0xFF3FFF8B);
  static const _greenDark = Color(0xFF2E7D32);
  static const _bgDark    = Color(0xFF0D1F12);
  static const _bgLight   = Color(0xFFF0FDF4);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.receiptHash == null) return const SizedBox.shrink();

    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final accent    = isDark ? _green    : _greenDark;
    final bg        = isDark ? _bgDark   : _bgLight;
    final border    = accent.withValues(alpha: 0.20);
    final textMid   = isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.45);
    final textMain  = isDark ? Colors.white : Colors.black;

    final hash      = widget.receiptHash!;
    final shortHash = '${hash.substring(0, 8)}...${hash.substring(hash.length - 8)}';

    return Container(
      margin: const EdgeInsets.only(top: 32),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 0.75),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Collapsed header ──────────────────────────
          GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _ShieldIcon(accent: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tamper-Evident Audit Receipt',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textMain,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          shortHash,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: textMid,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded content ──────────────────────────
          if (_expanded)
            FadeTransition(
              opacity: _fadeIn,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(height: 0.5, thickness: 0.5, color: border),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Meta rows
                        _Row(label: 'Standard',  value: widget.receiptVersion ?? 'HUSTLR-AUDIT-V1', accent: accent, textMid: textMid, textMain: textMain),
                        _Row(label: 'Algorithm', value: 'SHA-256',                                  accent: accent, textMid: textMid, textMain: textMain),
                        _Row(label: 'Generated', value: _fmtTs(widget.generatedAt),                 accent: accent, textMid: textMid, textMain: textMain),

                        // Payload snapshot if available
                        if (widget.receiptPayload != null) ...[
                          const SizedBox(height: 12),
                          Text('Locked values', style: TextStyle(fontSize: 10, color: textMid)),
                          const SizedBox(height: 6),
                          _PayloadChips(payload: widget.receiptPayload!, accent: accent, bg: bg, border: border, textMain: textMain, textMid: textMid),
                        ],

                        const SizedBox(height: 14),

                        // Full hash + copy
                        Text('Full hash', style: TextStyle(fontSize: 10, color: textMid)),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: hash));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Receipt hash copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: border, width: 0.5),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    hash,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontFamily: 'monospace',
                                      color: accent,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.copy_rounded, size: 13, color: textMid),
                              ],
                            ),
                          ),
                        ),

                        // Explanation
                        const SizedBox(height: 14),
                        Text(
                          'Every trigger reading, fraud score, zone depth, and payout '
                          'figure was cryptographically locked at the moment this claim '
                          'was approved. Any modification to this claim after approval '
                          'will break this hash — making tampering detectable.',
                          style: TextStyle(
                            fontSize: 11,
                            color: textMid,
                            height: 1.6,
                          ),
                        ),

                        const SizedBox(height: 10),
                        Text(
                          'Verify independently →',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accent,
                            decoration: TextDecoration.underline,
                            decorationColor: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _fmtTs(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
             '${dt.month.toString().padLeft(2, '0')}/'
             '${dt.year}  '
             '${dt.hour.toString().padLeft(2, '0')}:'
             '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _ShieldIcon extends StatelessWidget {
  final Color accent;
  const _ShieldIcon({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.verified_outlined, size: 17, color: accent),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final Color textMid;
  final Color textMain;

  const _Row({
    required this.label,
    required this.value,
    required this.accent,
    required this.textMid,
    required this.textMain,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: TextStyle(fontSize: 11, color: textMid)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textMain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayloadChips extends StatelessWidget {
  final Map<String, dynamic> payload;
  final Color accent;
  final Color bg;
  final Color border;
  final Color textMain;
  final Color textMid;

  const _PayloadChips({
    required this.payload,
    required this.accent,
    required this.bg,
    required this.border,
    required this.textMain,
    required this.textMid,
  });

  @override
  Widget build(BuildContext context) {
    // Show a curated subset of the payload as human readable chips
    final display = <MapEntry<String, String>>[
      if (payload['trigger_type']     != null) MapEntry('Trigger',    payload['trigger_type'].toString()),
      if (payload['trigger_value']    != null) MapEntry('Value',      payload['trigger_value'].toString()),
      if (payload['gross_payout']     != null) MapEntry('Gross',      '₹${payload["gross_payout"]}'),
      if (payload['plan_tier']        != null) MapEntry('Plan',       payload['plan_tier'].toString()),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: display.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border, width: 0.5),
          ),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${e.key}  ',
                  style: TextStyle(fontSize: 10, color: textMid),
                ),
                TextSpan(
                  text: e.value,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textMain),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
