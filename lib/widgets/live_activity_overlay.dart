import 'package:flutter/material.dart';
import '../services/shift_tracking_service.dart';
import '../services/shift_tracking_notifier.dart';
import '../services/storage_service.dart';

class LiveActivityOverlay extends StatefulWidget {
  final Widget child;
  const LiveActivityOverlay({required this.child, super.key});

  @override
  State<LiveActivityOverlay> createState() => _LiveActivityOverlayState();
}

class _LiveActivityOverlayState extends State<LiveActivityOverlay> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  bool _shiftActive = false;
  bool _triggerActive = false;
  String _statusText = 'Protected';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    ShiftTrackingNotifier.instance.addListener(_onTrackingUpdate);
    _checkShiftState();
  }

  void _checkShiftState() {
    if (mounted) {
      setState(() => _shiftActive = ShiftTrackingService.instance.status == ShiftStatus.active);
    }
  }

  void _onTrackingUpdate() {
    if (!mounted) return;
    setState(() {
      _shiftActive = ShiftTrackingNotifier.instance.isActive;
      _triggerActive = ShiftTrackingNotifier.instance.hasTrigger;
      _statusText = _triggerActive ? 'Disruption Detected!' : 'Protected';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        if (_shiftActive)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Material(
              type: MaterialType.transparency,
              child: _buildLivePill(),
            ),
          ),
      ],
    );
  }

  Widget _buildLivePill() {
    // Using simple opacity instead of withOpacity deprecation warnings if possible, but code used it.
    final color = _triggerActive ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    
    return GestureDetector(
      onTap: _showStatusBottomSheet,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 8 * _pulseAnimation.value,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 4 * _pulseAnimation.value,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _triggerActive ? '⚡ $_statusText' : '🛡 $_statusText',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showStatusBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Shift Protection Active',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _statusRow('Zone', StorageService.userZone.isNotEmpty ? StorageService.userZone : 'Unknown'),
            _statusRow('Last GPS update', _formatTime()),
            _statusRow('Zone depth score', '9.82'),
            _statusRow('Monitoring', '9 triggers — every 15 min'),
            _statusRow('Coverage', 'Standard Shield · ₹49/week'),
            const SizedBox(height: 16),
            if (_triggerActive)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Text(
                  '⚡ Disruption detected in your zone — claim processing',
                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  String _formatTime() {
    final dt = ShiftTrackingNotifier.instance.lastGpsUpdate;
    if (dt == null) return 'Waiting...';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  void dispose() {
    _pulseController.dispose();
    ShiftTrackingNotifier.instance.removeListener(_onTrackingUpdate);
    super.dispose();
  }
}
