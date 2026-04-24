import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/api_service.dart';

/// Optional [extra]: raw FPS-style map → POST `/claims/explanation`, or a map that
/// already contains `reasons` (and optional `summary`).
class AutoExplanationScreen extends StatefulWidget {
  const AutoExplanationScreen({super.key, this.extra});

  final Map<String, dynamic>? extra;

  @override
  State<AutoExplanationScreen> createState() => _AutoExplanationScreenState();
}

class _AutoExplanationScreenState extends State<AutoExplanationScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _reasons = [];
  String? _summary;

  static final List<Map<String, dynamic>> _demoReasons = [
    {
      'title': 'Home network detected',
      'detail':
          'Your Wi-Fi showed a home SSID during the disruption window',
      'severity': 'warning',
    },
    {
      'title': 'No outdoor motion',
      'detail':
          'Your device motion was below your usual outdoor work pattern',
      'severity': 'warning',
    },
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = widget.extra;
    if (x == null) {
      setState(() {
        _reasons = List<Map<String, dynamic>>.from(
            _demoReasons.map((e) => Map<String, dynamic>.from(e)));
        _loading = false;
      });
      return;
    }

    final pre = x['reasons'];
    if (pre is List) {
      final list = pre
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      setState(() {
        _reasons = list;
        _summary = x['summary']?.toString();
        _loading = false;
      });
      return;
    }

    final res = await ApiService.instance.postClaimExplanation(x);
    if (!mounted) return;
    final reasons = res['reasons'];
    setState(() {
      if (reasons is List) {
        _reasons = reasons
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
      _summary = res['summary']?.toString();
      _loading = false;
    });
  }

  Color _severityColor(String? s) {
    switch (s) {
      case 'critical':
        return Colors.redAccent;
      case 'warning':
        return Colors.deepOrange;
      default:
        return Colors.blueGrey;
    }
  }

  IconData _iconFor(String title) {
    final t = title.toLowerCase();
    if (t.contains('wifi') || t.contains('wi-fi') || t.contains('wi‑fi')) {
      return Icons.wifi_rounded;
    }
    if (t.contains('gps') || t.contains('zone')) return Icons.location_off_rounded;
    if (t.contains('play')) return Icons.verified_user_rounded;
    if (t.contains('mock')) return Icons.map_rounded;
    if (t.contains('latency')) return Icons.timer_off_rounded;
    if (t.contains('barometer')) return Icons.speed_rounded;
    if (t.contains('motion') || t.contains('outdoor')) {
      return Icons.directions_walk_rounded;
    }
    if (t.contains('offline') || t.contains('manual')) {
      return Icons.info_outline_rounded;
    }
    return Icons.warning_amber_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.canvasColor,
      appBar: AppBar(
        title: const Text(
          'Why your claim was flagged',
          style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.redAccent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 72),
                  const SizedBox(height: 24),
                  Text(
                    _summary != null && _summary!.isNotEmpty
                        ? _summary!
                        : 'Our engine detected the following signals:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ..._reasons.expand((r) {
                    final title = r['title']?.toString() ?? 'Signal';
                    final detail = r['detail']?.toString() ?? '';
                    final sev = r['severity']?.toString();
                    final c = _severityColor(sev);
                    return [
                      _buildSignalItem(
                        _iconFor(title),
                        title,
                        detail,
                        theme,
                        isDark,
                        accent: c,
                      ),
                      const SizedBox(height: 16),
                    ];
                  }),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.04),
                        width: 1.5,
                      ),
                      boxShadow: isDark
                          ? []
                          : [
                              const BoxShadow(
                                color: Color(0x05000000),
                                blurRadius: 16,
                                offset: Offset(0, 8),
                              )
                            ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'If you were genuinely affected, appeal below. We review within 4 hours.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor:
                                  isDark ? theme.canvasColor : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Opening camera for EXIF photo...'),
                                ),
                              );
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Submit Appeal',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, size: 20),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'First-time flags are treated as caution only.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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

  Widget _buildSignalItem(
    IconData icon,
    String title,
    String detail,
    ThemeData theme,
    bool isDark, {
    Color accent = Colors.redAccent,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.2), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: accent,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
