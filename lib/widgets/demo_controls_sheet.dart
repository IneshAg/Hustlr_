import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'package:provider/provider.dart';
import '../services/mock_data_service.dart';
import '../services/location_service.dart';
import '../services/fraud_sensor_service.dart';
import '../core/router/app_router.dart';

class DemoControlsSheet extends StatefulWidget {
  const DemoControlsSheet({super.key});

  @override
  State<DemoControlsSheet> createState() => _DemoControlsSheetState();
}

class _DemoControlsSheetState extends State<DemoControlsSheet> {
  int _activePersona = -1;
  bool _isRunning = false;

  // ── Persona definitions ──────────────────────────────────────────────────
  static const List<Map<String, dynamic>> PERSONAS = [
    {
      'id': 'karthik',
      'name': 'Karthik, 24',
      'role': 'Standard Shield · Adyar Zone',
      'icon': '🚲',
      'color': Color(0xFF1976D2),
      'bg': Color(0xFFE3F2FD),
      'tagline': 'Full parametric loop — rain → claim → payout',
      'features': [
        'Rain disruption auto-detected',
        'Fraud check passes (FPS 14)',
        'Tranche 1 (70%) credited in minutes',
        'Notification bell updates live',
        'Wallet balance increases',
      ],
      'steps': [
        'Rain alert appears on dashboard',
        'Claim created → PENDING',
        'Auto-approved in 3 seconds',
        'Wallet credited ₹105',
        'Push notification sent',
      ],
    },
    {
      'id': 'ravi',
      'name': 'Ravi, 31',
      'role': 'Full Shield · Velachery Zone',
      'icon': '⚡',
      'color': Color(0xFFE65100),
      'bg': Color(0xFFFFF3E0),
      'tagline': 'Compound trigger — rain + platform outage',
      'features': [
        'Two triggers fire simultaneously',
        'Compound payout (130% rate)',
        'Full Shield daily cap ₹250',
        'Shadow policy tracking shown',
        'Predictive nudge displayed',
      ],
      'steps': [
        'Platform outage detected (78% failure rate)',
        'Rain cross-confirmed by IMD',
        'Compound trigger fires',
        'Payout ₹245 (compound rate)',
        'Wednesday nudge scheduled',
      ],
    },
    {
      'id': 'muthu',
      'name': 'Muthu, 28',
      'role': 'No Policy · Tambaram Zone',
      'icon': '📊',
      'color': Color(0xFF6A1B9A),
      'bg': Color(0xFFF3E5F5),
      'tagline': 'Shadow policy — conversion nudge demo',
      'features': [
        'Uninsured worker tracked silently',
        'Missed payout calculated (₹680)',
        'Shadow policy nudge shown',
        'Policy comparison screen opens',
        'One-tap enrolment flow',
      ],
      'steps': [
        'Rain disruption hits Tambaram zone',
        'Shadow policy calculates ₹340 missed',
        'Second event adds ₹340 more',
        'Nudge: "You missed ₹680 this fortnight"',
        'Activate Standard Shield CTA shown',
      ],
    },
    {
      'id': 'fraudster',
      'name': 'Fraud Attempt',
      'role': 'GPS Spoofer · Adyar Zone',
      'icon': '🛡️',
      'color': Color(0xFFB71C1C),
      'bg': Color(0xFFFFEBEE),
      'tagline': 'Fraud engine catches GPS spoofing in real time',
      'features': [
        'Zero GPS jitter detected',
        'FPS score spikes to 87',
        'Claim auto-flagged RED',
        'Provisional ₹200 only',
        'Human review queued',
      ],
      'steps': [
        'Claim submitted with gps_jitter=0.0',
        'Isolation Forest: anomaly detected',
        'Zero jitter override: FPS → 87',
        'Status: FLAGGED (not APPROVED)',
        'Auto-explanation sent to worker',
      ],
    },
    {
      'id': 'santhosh',
      'name': 'Santhosh, 26',
      'role': 'Standard Shield · OMR Zone',
      'icon': '🏆',
      'color': Color(0xFF1B5E20),
      'bg': Color(0xFFE8F5E9),
      'tagline': 'Trust score + cashback — 4 clean weeks',
      'features': [
        'Worker Trust Score shown',
        'Gold tier badge displayed',
        'Clean week streak: 4 weeks',
        'Cashback ₹19.60 auto-credited',
        'Profile trust tier updated',
      ],
      'steps': [
        'Load worker with 4 clean weeks',
        'Sunday settlement triggers cashback',
        '10% of premiums returned (₹19.60)',
        'Trust score → 127 (Gold tier)',
        'Wallet shows cashback credit',
      ],
    },
    {
      'id': 'priya',
      'name': 'Priya, 33',
      'role': 'Standard Shield · T.Nagar Zone',
      'icon': '🌐',
      'color': Color(0xFF00695C),
      'bg': Color(0xFFE0F2F1),
      'tagline': 'Internet zone blackout trigger',
      'features': [
        'Zone connectivity drops to 8%',
        'TRAI outage signal detected',
        'Blackout trigger fires automatically',
        'Payout ₹110 credited',
        'No GPS needed — self-validating',
      ],
      'steps': [
        'Ookla: T.Nagar avg speed 0.3 Mbps',
        'TRAI registry: Airtel outage logged',
        'Dual confirmation → AUTO_TRIGGER',
        'Claim created: internet_blackout',
        'Payout ₹77 (70% tranche)',
      ],
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF141614) : Colors.white;
    final surface = isDark ? const Color(0xFF1C1F1C) : const Color(0xFFF4F6F4);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Demo Controls',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFFE1E3DE)
                              : const Color(0xFF0D1B0F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select a persona to demo a specific feature set',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF91938D)
                              : const Color(0xFF4A6741),
                        ),
                      ),
                    ],
                  ),
                ),
                // Test Notification button
                TextButton(
                  onPressed: () {
                    NotificationService.instance.addWalletCredited(amount: 500);
                  },
                  child: const Text(
                    'Test Notif',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // Reset button
                TextButton(
                  onPressed: _hardReset,
                  child: const Text(
                    'Reset',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF2E7D32), // Green for "return to live"
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PERSONA SCENARIOS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      color: isDark
                          ? const Color(0xFF91938D)
                          : const Color(0xFF4A6741),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(PERSONAS.length, (i) {
                    final p = PERSONAS[i];
                    final isActive = _activePersona == i;
                    final color = p['color'] as Color;
                    final cardBg = p['bg'] as Color;

                    return GestureDetector(
                      onTap: _isRunning ? null : () => _runPersona(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? (isDark
                                  ? color.withValues(alpha: 0.15)
                                  : cardBg)
                              : (isDark
                                  ? const Color(0xFF1C1F1C)
                                  : Colors.white),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive
                                ? color
                                : theme.dividerColor.withValues(alpha: 0.08),
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 10),
                              child: Row(
                                children: [
                                  Text(p['icon'] as String,
                                      style: const TextStyle(fontSize: 24)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p['name'] as String,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? const Color(0xFFE1E3DE)
                                                : const Color(0xFF0D1B0F),
                                          ),
                                        ),
                                        Text(
                                          p['role'] as String,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? const Color(0xFF91938D)
                                                : const Color(0xFF4A6741),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isActive && _isRunning)
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: color),
                                    )
                                  else if (isActive && !_isRunning)
                                    Icon(Icons.check_circle,
                                        color: color, size: 20)
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? color.withValues(alpha: 0.15)
                                            : cardBg,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Run',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                              child: Text(
                                p['tagline'] as String,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: color),
                              ),
                            ),
                            if (isActive) ...[
                              const Divider(height: 1),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 10, 16, 4),
                                child: Text(
                                  'FEATURES DEMONSTRATED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? const Color(0xFF91938D)
                                        : const Color(0xFF4A6741),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              ...(p['features'] as List<String>).map(
                                (f) => Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 2, 16, 2),
                                  child: Row(
                                    children: [
                                      Icon(Icons.check, size: 13, color: color),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          f,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? const Color(0xFFE1E3DE)
                                                : const Color(0xFF0D1B0F),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_isRunning) ...[
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 10, 16, 4),
                                  child: Text(
                                    'DEMO SEQUENCE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? const Color(0xFF91938D)
                                          : const Color(0xFF4A6741),
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                ...(p['steps'] as List<String>)
                                    .asMap()
                                    .entries
                                    .map(
                                      (e) => Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 2, 16, 2),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 18,
                                              height: 18,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: color.withValues(
                                                    alpha: 0.15),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Text(
                                                '${e.key + 1}',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: color,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                e.value,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? const Color(0xFF91938D)
                                                      : const Color(0xFF4A6741),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              ],
                              const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),

                  // --- SIMULATE ROAMING / HUB PROXIMITY ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.map_rounded,
                                color: theme.colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text('ROAMING SIMULATOR',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                    color: theme.colorScheme.primary)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _hubSimButton('Kattankulathur', 12.8185, 80.0419),
                            _hubSimButton('Adyar (Flood)', 13.0067, 80.2206),
                            _hubSimButton('HSR (Outage)', 12.9081, 77.6476),
                            _hubSimButton('Indiranagar', 12.9784, 77.6408),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                            'Tap to teleport persona to a Dark Store Hub. Hudson will detect the move instantly.',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5))),
                      ],
                    ),
                  ),

                  // --- ML SYNC ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(top: 16),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sync_rounded,
                                color: theme.colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text('ML SYNC',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                    color: theme.colorScheme.primary)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // --- Force ML Resync ---
                        _internalControlRow(
                          theme: theme,
                          title: 'Force ML Resync',
                          subtitle: 'Pulls latest ISS & Pricing from proxy',
                          buttonLabel: 'SYNC NOW',
                          buttonColor: theme.colorScheme.primary,
                          onTap: () {
                            LocationService.instance
                                .addEvent("ML Data Synced from Python Backend");
                            _showSuccess("ML synchronization requested.");
                          },
                        ),
                        const SizedBox(height: 12),
                        // --- Dynamic Calculation ---
                        _internalControlRow(
                          theme: theme,
                          title: 'Dynamic ISS Recalculation',
                          subtitle:
                              'Re-runs ISS + premium pricing model with live inputs',
                          buttonLabel: 'RECALCULATE',
                          buttonColor: Colors.teal,
                          onTap: () async {
                            try {
                              final mock = context.read<MockDataService>();
                              final issRes =
                                  await ApiService.instance.getIssScore();
                              final score =
                                  (issRes['iss_score'] as num?)?.toInt() ?? 65;

                              final premiumRes = await ApiService.instance
                                  .getDynamicPremium(
                                      mock.activePolicy.plan, score);
                              final premium =
                                  (premiumRes['premium'] as num?)?.toDouble() ??
                                      49.0;

                              mock.updateIssAndPricing(score, premium);
                              _showSuccess(
                                  "ISS & premium pricing recalculated.");
                            } catch (_) {
                              _showSuccess(
                                  "ISS recalculation queued (backend offline).");
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // --- EXTERNAL DISRUPTIONS POPUP BUTTON ---
                  GestureDetector(
                    onTap: _showExternalDisruptionsPopup,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(top: 16),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: Colors.blueAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_rounded,
                              color: Colors.blueAccent, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('EXTERNAL DISRUPTIONS',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.blueAccent)),
                                const SizedBox(height: 4),
                                Text('Trigger weather, platform events',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.blueAccent
                                            .withValues(alpha: 0.7))),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: Colors.blueAccent),
                        ],
                      ),
                    ),
                  ),

                  // --- FRAUD SIGNALS ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(top: 16),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Force-inject fraud signals to test the detection engine',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.45))),
                        const SizedBox(height: 16),
                        // GPS spoof toggle
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Mock GPS Spoofing',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600)),
                                  Text(
                                      'Sets jitter=0.0, isMocked=true -> triggers fraud flag',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.5))),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Switch(
                              value: FraudSensorService.mockFraudSpoofing,
                              activeThumbColor: Colors.redAccent,
                              onChanged: (val) => setState(() =>
                                  FraudSensorService.mockFraudSpoofing = val),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _internalControlRow(
                          theme: theme,
                          title: 'Inject High Fraud Score',
                          subtitle:
                              'Sets mock FPS to 95 - triggers immediate fraud review',
                          buttonLabel: 'INJECT',
                          buttonColor: Colors.redAccent,
                          onTap: () {
                            FraudSensorService.mockFraudSpoofing = true;
                            LocationService.instance
                                .addEvent("Fraud score injected: FPS 95");
                            setState(() {});
                            _showSuccess(
                                "Fraud score set to 95. Claim will be auto-flagged.");
                          },
                        ),
                        const SizedBox(height: 12),
                        _internalControlRow(
                          theme: theme,
                          title: 'Clear Fraud Signals',
                          subtitle:
                              'Resets all mock fraud overrides to clean state',
                          buttonLabel: 'CLEAR',
                          buttonColor: Colors.green,
                          onTap: () {
                            FraudSensorService.mockFraudSpoofing = false;
                            LocationService.instance
                                .addEvent("Fraud signals cleared");
                            setState(() {});
                            _showSuccess("Fraud signals cleared.");
                          },
                        ),
                      ],
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

  Widget _hubSimButton(String label, double lat, double lon) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: () {
        LocationService.instance
            .forceMockLocation(label, lat, lon, depthScore: 0.95);
        _showStep('Teleported to $label Hub');
      },
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side:
            BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface)),
    );
  }

  /// A fixed-layout control row that won't overflow text vertically.
  /// Uses [Column] + [Row] instead of [ListTile] with trailing button.
  Widget _internalControlRow({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required Color buttonColor,
    required VoidCallback onTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5))),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: buttonColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(buttonLabel,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5)),
        ),
      ],
    );
  }

  // ── Persona runners ──────────────────────────────────────────────────────

  Future<void> _runPersona(int index) async {
    if (!mounted) return;
    setState(() {
      _activePersona = index;
      _isRunning = true;
    });

    final persona = PERSONAS[index];

    // Switch the active persona globally first
    await MockDataService.instance.switchPersona(persona['id'] as String);

    switch (persona['id'] as String) {
      case 'karthik':
        await _runKarthik();
        break;
      case 'ravi':
        await _runRavi();
        break;
      case 'muthu':
        await _runMuthu();
        break;
      case 'fraudster':
        await _runFraudster();
        break;
      case 'santhosh':
        await _runSanthosh();
        break;
      case 'priya':
        await _runPriya();
        break;
    }

    if (!mounted) return;
    setState(() => _isRunning = false);
  }

  // Karthik — standard rain claim, full parametric loop
  Future<void> _runKarthik() async {
    final userId = StorageService.userId;
    if (userId.isEmpty) {
      _showError('Please log in first to run this persona.');
      return;
    }

    try {
      // 1. Show rain alert on dashboard
      _showStep('Rain alert firing in Adyar zone...');
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      // 2. Create claim
      _showStep('Creating rain claim...');
      context.read<MockDataService>().triggerRainDisruption();

      // 3. Fire notification
      NotificationService.instance.addClaimCreated(
        triggerType: 'Heavy Rain',
        amount: 105,
      );

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      _showStep('Claim auto-approved...');
      NotificationService.instance.addClaimApproved(105);
      NotificationService.instance.addWalletCredited(amount: 105);

      _showSuccess(
          'Karthik received â‚¹105. Navigate to Claims and Wallet to see.');
    } catch (e) {
      _showError('Demo error: $e');
    }
  }

  // Ravi â€” compound trigger
  Future<void> _runRavi() async {
    final userId = StorageService.userId;
    if (userId.isEmpty) return;

    try {
      _showStep('Platform outage detected (78% failure rate)...');
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      _showStep('Rain cross-confirmed by IMD...');
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      _showStep('Compound trigger firing...');
      context.read<MockDataService>().triggerCompoundDisruption();

      NotificationService.instance.addDisruptionAlert(
        triggerType: 'Platform + Rain (Compound)',
        zone: 'Velachery Dark Store Zone',
      );

      _showSuccess('Compound payout â‚¹245 processing. '
          'Check Claims tab â€” trigger shows compound rate.');
    } catch (e) {
      _showError('Demo error: $e');
    }
  }

  // Muthu — shadow policy nudge
  Future<void> _runMuthu() async {
    _showStep('Applying Muthu shadow-policy scenario...');
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // Initialize mock data for the shadow policy showcase
    final mockSvc = context.read<MockDataService>();
    mockSvc.missedAmount = 680;
    mockSvc.shadowEvents = [
      ShadowEventModel(
          triggerIcon: "rain",
          triggerName: "Rain Disruption",
          date: "Oct 12, 2025",
          claimableAmount: 320),
      ShadowEventModel(
          triggerIcon: "downtime",
          triggerName: "Platform Downtime",
          date: "Oct 8, 2025",
          claimableAmount: 360),
    ];
    mockSvc.hasActivePolicy = false;
    mockSvc.notifyListeners();

    if (mounted) {
      context.go('/dashboard');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Muthu persona active: Tambaram zone, no policy, shadow nudge enabled.'),
          backgroundColor: Color(0xFF1B5E20),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Fraudster - fraud engine demo
  Future<void> _runFraudster() async {
    final userId = StorageService.userId;
    if (userId.isEmpty) return;

    _showStep('Submitting claim with gps_jitter = 0.0 (spoofed GPS)...');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    _showStep('Isolation Forest scoring...');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    _showStep('Zero jitter override â†’ FPS score: 87 â†’ RED');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    // Create a claim that will be flagged
    try {
      context.read<MockDataService>().triggerFraudAttempt();
    } catch (e) {
      // Even if API doesn't support extra fields, show the UI
    }

    _showSuccess(
      'Claim FLAGGED â€” FPS 87 â†’ RED â†’ Human review queued.\n'
      'Check Claims tab â€” status shows FLAGGED not APPROVED.\n'
      'Only â‚¹200 provisional credit released.',
    );
  }

  // Santhosh â€” trust score + cashback
  Future<void> _runSanthosh() async {
    _showStep('Loading 4 clean weeks history...');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    _showStep('Sunday settlement: cashback calculation...');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    _showStep('10% of â‚¹196 premiums = â‚¹19.60 cashback credited...');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    context.read<MockDataService>().creditWalletForDemo(
          amount: 20,
          title: 'Trust Cashback',
          subtitle: '4 clean weeks bonus',
          addToSavings: false,
        );
    NotificationService.instance.addWalletCredited(amount: 20);

    if (!mounted) return;
    context.push('${AppRoutes.profile}?demo=trust_score');
  }

  // Priya â€” internet blackout
  Future<void> _runPriya() async {
    final userId = StorageService.userId;
    if (userId.isEmpty) return;

    _showStep('Ookla: T.Nagar avg speed 0.3 Mbps...');
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    _showStep('TRAI registry: Airtel outage logged...');
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    _showStep('Dual confirmation â†’ AUTO_TRIGGER...');
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    try {
      context.read<MockDataService>().triggerInternetBlackout();

      NotificationService.instance.addClaimCreated(
        triggerType: 'Internet Zone Blackout',
        amount: 77,
      );

      _showSuccess(
        'Internet blackout claim created.\n'
        'No GPS required â€” self-validating trigger.\n'
        'Payout â‚¹77 (70% tranche).',
      );
    } catch (e) {
      _showError('Demo error: $e');
    }
  }

  Future<void> _hardReset() async {
    // Complete wipe of all mock data â€” restore app to pristine state
    final mockSvc = context.read<MockDataService>();
    mockSvc.clearAllMockData();

    LocationService.instance.addEvent("ðŸ”„ Hard reset: All mock data cleared");

    if (mounted) {
      setState(() {});
      _showSuccess("All mock data cleared. App restored to pristine state.");
      Navigator.pop(context);
    }
  }

  void _showStep(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 900),
        backgroundColor: const Color(0xFF1B5E20),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showExternalDisruptionsPopup() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1F1C) : Colors.white;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.cloud_rounded,
                        color: Colors.blueAccent, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('External Disruptions',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface)),
                          Text('Trigger weather and platform events',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6))),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Heavy Rain
                _internalControlRow(
                  theme: theme,
                  title: 'Heavy Rain Alert',
                  subtitle:
                      'Mocks OWM weather alert â†’ auto-creates rain claim',
                  buttonLabel: 'FIRE',
                  buttonColor: Colors.blueAccent,
                  onTap: () {
                    context.read<MockDataService>().triggerRainDisruption();
                    Navigator.pop(context);
                    _showSuccess("Rain disruption triggered!");
                  },
                ),
                const SizedBox(height: 16),

                // Extreme Heatwave
                _internalControlRow(
                  theme: theme,
                  title: 'Extreme Heatwave',
                  subtitle: 'Mocks temperature spike beyond 42Â°C threshold',
                  buttonLabel: 'FIRE',
                  buttonColor: Colors.orangeAccent,
                  onTap: () {
                    context.read<MockDataService>().triggerExtremeHeat();
                    Navigator.pop(context);
                    _showSuccess("Heatwave disruption triggered!");
                  },
                ),
                const SizedBox(height: 16),

                // Platform Outage
                _internalControlRow(
                  theme: theme,
                  title: 'Platform Outage',
                  subtitle: 'Simulates Swiggy/Zepto order failure rate >75%',
                  buttonLabel: 'FIRE',
                  buttonColor: Colors.redAccent,
                  onTap: () {
                    context.read<MockDataService>().triggerPlatformDowntime();
                    Navigator.pop(context);
                    _showSuccess("Platform outage disruption triggered!");
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF1B5E20), size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child:
                const Text('Done', style: TextStyle(color: Color(0xFF2E7D32))),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFB71C1C),
      ),
    );
  }
}
