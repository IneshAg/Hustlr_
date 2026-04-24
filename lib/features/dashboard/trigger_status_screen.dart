import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../services/app_events.dart';

class TriggerStatusScreen extends StatefulWidget {
  const TriggerStatusScreen({super.key});

  @override
  State<TriggerStatusScreen> createState() => _TriggerStatusScreenState();
}

class _TriggerStatusScreenState extends State<TriggerStatusScreen> {
  List<dynamic> _liveStatus = [];
  bool _isLoading = true;
  String _userZone = 'Local Zone';

  @override
  void initState() {
    super.initState();
    _loadData();
    AppEvents.instance.onPolicyUpdated.listen((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final zone = await StorageService.instance.getUserZone() ?? 'Adyar Dark Store Zone';
      _userZone = zone;

      final res = await ApiService.instance.getDisruptionsInstance(zone);
      
      if (mounted) {
        setState(() {
          _liveStatus = res['disruptions'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _liveStatus = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.canvasColor,
      appBar: AppBar(
        title: Text('Live Trigger Monitoring', style: TextStyle(fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface, letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
               children: [
                Icon(Icons.radar_rounded, color: theme.colorScheme.primary, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Auto-monitoring $_userZone every 15 mins',
                  style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _liveStatus.isEmpty
                    ? _buildEmptyState(theme, isDark)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        physics: const BouncingScrollPhysics(),
                        itemCount: _liveStatus.length,
                        itemBuilder: (context, index) => _buildDynamicTriggerDetailCard(_liveStatus[index], theme, isDark),
                      ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(Icons.bolt_rounded, color: theme.colorScheme.primary, size: 18),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'All triggers monitored automatically. You never need to check this — Hustlr notifies you by Sunday 11 PM.',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), height: 1.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shield_outlined, size: 48, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 24),
          Text(
            'Clear Skies Ahead',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'There are no active triggers or disruptions tracked in $_userZone right now. Hustle safe!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.6), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicTriggerDetailCard(Map<String, dynamic> disruption, ThemeData theme, bool isDark) {
    // Map backend properties to UI
    final type = disruption['trigger_type'] ?? 'unknown';
    final name = disruption['display_name'] ?? 'Disruption Alert';
    final reading = disruption['current_value'] ?? 'Tracking dynamically';
    final threshold = disruption['threshold'] ?? 'Warning Level';
    final source = (disruption['data_sources'] as List?)?.join(', ') ?? 'Govt Sensor Network';
    final rate = '₹${disruption['hourly_rate'] ?? 40}/hr';
    final severity = (disruption['severity'] as num?)?.toDouble() ?? 1.0;
    
    // Logic mapping
    final isElevated = severity >= 0.8;
    final emoji = _getEmojiForType(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isElevated ? Colors.orange : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04)),
          width: isElevated ? 2 : 1.5,
        ),
        boxShadow: isDark ? [] : [
           BoxShadow(color: isElevated ? Colors.orange.withValues(alpha: 0.1) : const Color(0x05000000), blurRadius: 16, offset: const Offset(0, 8)),
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
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: (isElevated ? Colors.orange : theme.colorScheme.primary).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
                  ),
                  const SizedBox(width: 14),
                  Text(name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.onSurface, letterSpacing: -0.3)),
                ],
              ),
              _statusBadge(isElevated ? 'ELEVATED' : 'ACTIVE', theme, isDark),
            ],
          ),
          const SizedBox(height: 20),
          _infoRow('Current reading', reading, theme),
          _infoRow('Trigger threshold', threshold, theme),
          _infoRow('Data source', source, theme),
          _infoRow('If triggered', rate, theme, true),
          
          if (isElevated) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Getting close to critical threshold. If condition worsens during your shift, $rate activates automatically.',
                      style: const TextStyle(color: Colors.orange, fontSize: 13, height: 1.4, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getEmojiForType(String type) {
    type = type.toLowerCase();
    if (type.contains('heat') || type.contains('temperature')) return '🥵';
    if (type.contains('rain') || type.contains('water')) return '🌧️';
    if (type.contains('cyclone') || type.contains('wind')) return '🌀';
    if (type.contains('bandh') || type.contains('riot')) return '🚧';
    return '⚠️';
  }

  Widget _statusBadge(String status, ThemeData theme, bool isDark) {
    final bool isElevated = status == 'ELEVATED';
    final color = isElevated ? Colors.orange : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
          color: color,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, ThemeData theme, [bool isHighlight = false]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 13, fontWeight: FontWeight.w700))),
          Expanded(flex: 3, child: Text(
            value,
            style: TextStyle(
              color: isHighlight ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              fontSize: 13,
              fontWeight: isHighlight ? FontWeight.w900 : FontWeight.w700,
            ),
          )),
        ],
      ),
    );
  }
}
