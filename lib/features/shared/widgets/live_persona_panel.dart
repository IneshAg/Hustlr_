import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/claims/claims_bloc.dart';
import '../../../blocs/claims/claims_event.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../services/app_events.dart';

void showLivePersonaPanel(BuildContext context, {VoidCallback? onSubmit}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: const LivePersonaPanel(),
      );
    },
  ).then((_) {
    if (onSubmit != null) onSubmit();
  });
}

class LivePersonaPanel extends StatefulWidget {
  const LivePersonaPanel({super.key});

  @override
  State<LivePersonaPanel> createState() => _LivePersonaPanelState();
}

class _LivePersonaPanelState extends State<LivePersonaPanel> {
  bool _isTriggering = false;
  String? _lastResult;

  Future<void> _setPersona({
    required int issScore,
    required String name,
    bool injectCyclone = false,
  }) async {
    if (_isTriggering) return;
    setState(() { _isTriggering = true; _lastResult = null; });

    try {
      final userId = await StorageService.instance.getUserId() ?? '';
      final zone = await StorageService.instance.getUserZone() ?? 'Adyar Dark Store Zone';

      if (userId.isEmpty) throw Exception('User ID not found — please log in first');

      // Step 1: Write the ISS score to the backend (PATCH /workers/:id/iss)
      await ApiService.instance.updateIssScore(userId, issScore);

      // Step 2 (Cyclone only): inject a live disruption event into backend memory
      if (injectCyclone) {
        await ApiService.createDisruption(
          zone: zone,
          triggerType: 'extreme_cyclone',
          severity: 1.0,
          startedAt: DateTime.now().toIso8601String(),
        );
      }

      // Fire app events — dashboard/wallet/claims all refresh organically
      AppEvents.instance.policyUpdated();
      AppEvents.instance.claimUpdated();
      AppEvents.instance.walletUpdated();

      if (mounted) {
        setState(() {
          _isTriggering = false;
          _lastResult = '✅ Persona: $name active! (ISS → $issScore)';
        });
        // Auto-dismiss after showing result
        Future.delayed(const Duration(milliseconds: 1800), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTriggering = false;
          _lastResult = '❌ Failed: $e';
        });
      }
    }
  }

  Future<void> _simulateClaim() async {
    if (_isTriggering) return;
    setState(() { _isTriggering = true; _lastResult = null; });
    try {
      final userId = await StorageService.instance.getUserId() ?? '';
      if (userId.isEmpty) throw Exception('User ID not found — please log in first');

      await ApiService.instance.submitManualClaim(
        userId: userId,
        disruptionType: 'heat_severe',
        description: 'Demo: Extreme heat disruption during shift',
      );
      AppEvents.instance.claimUpdated();
      AppEvents.instance.walletUpdated();
      if (mounted) {
        context.read<ClaimsBloc>().add(LoadClaims(userId));
      }

      if (mounted) {
        setState(() {
          _isTriggering = false;
          _lastResult = '✅ Claim submitted! Check the Claims tab.';
        });
        Future.delayed(const Duration(milliseconds: 1800), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTriggering = false;
          _lastResult = '❌ Failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF10B981), width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const Text(
            '🎭  Live Persona Simulator',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold,
              fontFamily: 'Manrope',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Each persona writes real data to the backend. The app then responds organically — showing real pricing, disruptions, fraud scores.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 12, fontFamily: 'Manrope'),
          ),
          const SizedBox(height: 20),

          // ── Personas ──
          _personaButton(
            emoji: '⭐',
            title: 'Star Worker',
            subtitle: 'ISS: 95 · Lowest premium · Max coverage',
            issScore: 95,
            color: const Color(0xFF10B981),
          ),
          const SizedBox(height: 10),
          _personaButton(
            emoji: '⚠️',
            title: 'Moderate Risk Worker',
            subtitle: 'ISS: 60 · Elevated premium · Standard coverage',
            issScore: 60,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 10),
          _personaButton(
            emoji: '🚨',
            title: 'High Fraud Risk',
            subtitle: 'ISS: 15 · ML flags anomalous patterns · Rejected claims',
            issScore: 15,
            color: const Color(0xFFEF4444),
          ),
          const SizedBox(height: 10),
          _personaButton(
            emoji: '🌀',
            title: 'Cyclone Week',
            subtitle: 'ISS: 45 + Severe Cyclone banner · Full parametric demo',
            issScore: 45,
            color: const Color(0xFF8B5CF6),
            isCyclone: true,
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(children: [
              Expanded(child: Divider(color: Color(0xFF30363D))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('ACTIONS', style: TextStyle(color: Color(0xFF8B949E), fontSize: 10, fontFamily: 'Manrope', fontWeight: FontWeight.bold)),
              ),
              Expanded(child: Divider(color: Color(0xFF30363D))),
            ]),
          ),

          // ── Simulate Claim ──
          GestureDetector(
            onTap: _isTriggering ? null : _simulateClaim,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2128),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Row(
                children: [
                  const Text('📋', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Simulate Claim Submission', style: TextStyle(
                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Manrope',
                        )),
                        Text('POST /claims/manual · Heat disruption · Initiates payout flow', style: TextStyle(
                          color: Color(0xFF8B949E), fontSize: 11, fontFamily: 'Manrope',
                        )),
                      ],
                    ),
                  ),
                  if (_isTriggering)
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  else
                    const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14),
                ],
              ),
            ),
          ),

          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: _lastResult!.startsWith('✅')
                    ? const Color(0xFF10B981).withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _lastResult!.startsWith('✅')
                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                      : Colors.redAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                _lastResult!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _lastResult!.startsWith('✅') ? const Color(0xFF10B981) : Colors.redAccent,
                  fontSize: 13,
                  fontFamily: 'Manrope',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _personaButton({
    required String emoji,
    required String title,
    required String subtitle,
    required int issScore,
    required Color color,
    bool isCyclone = false,
  }) {
    return GestureDetector(
      onTap: _isTriggering ? null : () => _setPersona(issScore: issScore, name: title, injectCyclone: isCyclone),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Manrope',
                  )),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(
                    color: Color(0xFF8B949E), fontSize: 11, fontFamily: 'Manrope',
                  )),
                ],
              ),
            ),
            if (_isTriggering)
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: color, strokeWidth: 2))
            else
              Icon(Icons.arrow_forward_ios_rounded, color: color.withValues(alpha: 0.6), size: 13),
          ],
        ),
      ),
    );
  }
}
