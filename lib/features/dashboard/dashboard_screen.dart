import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../services/location_service.dart';
import '../../services/mock_data_service.dart';

import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/router/app_router.dart';
import 'package:provider/provider.dart';
import '../../services/notification_service.dart';
import '../../shared/widgets/notification_bell.dart';
import '../../widgets/shift_status_dot.dart';
import '../../l10n/app_localizations.dart';
import '../../core/utils/pdf_generator.dart';
import '../../models/policy.dart';
import 'widgets/disruption_alert_overlay.dart';

import '../../features/shared/widgets/battery_optimization_prompt.dart';
import '../../services/shift_tracking_service.dart';
import '../../services/fraud_sensor_service.dart';
import '../../shared/widgets/offline_banner.dart';
import '../../shared/widgets/animated_skeleton.dart';

import '../../services/dynamic_translator.dart';
import '../../services/app_events.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const _dashboardSnapshotKey = 'dashboardSnapshotV1';
  final List<_SystemFeedEvent> _events = [
    _SystemFeedEvent('Dashboard initialized', DateTime.now()),
  ];

  Map<String, dynamic>? policyData;
  Map<String, dynamic>? walletData;
  Map<String, dynamic>? disruptionData;
  Map<String, dynamic>? weatherData;
  Map<String, dynamic>? nudgeData;
  Map<String, dynamic>? workAdvisorData;
  Map<String, dynamic>? activeDisruption;
  String? userId;
  String? userZone;
  String? userName;
  bool isLoading = true;
  bool _isGoingOnline =
      false; // separate flag so Go Online never blanks the whole dashboard
  Timer? _disruptionRefreshTimer;
  StreamSubscription<Position>? _locationStream;

  // Stream subscriptions
  StreamSubscription? _policySub;
  StreamSubscription? _walletSub;
  StreamSubscription? _claimSub;

  // Guard: prevents concurrent _loadDashboardData calls
  bool _isDashboardLoading = false;

  // Debounce timestamps for event-driven reloads
  int _lastWalletReload = 0;
  int _lastClaimReload = 0;

  int? liveIssScore;
  double? liveDynamicPrice;

  // Debug variables
  bool _debugMode = false;
  bool _enableLiveML = false;
  String _locationPermissionStatus = 'unknown';
  bool _backgroundTrackingActive = false;

  // Live pulled from LocationService.instance on every GPS tick
  double get _lastLat => LocationService.instance.currentLat;
  double get _lastLng => LocationService.instance.currentLon;
  double get _zoneDepthScore => LocationService.instance.depthScore * 100;

  // API health check results
  Map<String, String> _apiHealthStatus = {};
  bool _reverifyPromptOpen = false;

  /// Dedup guard: store the ID of the last disruption for which we showed the
  /// overlay — prevents re-showing the same alert on every 15-min data refresh.
  String? _lastShownDisruptionId;
  bool _disruptionOverlayOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLocationPermission();
    _fetchInitialLocation(); // ← get GPS fix immediately without waiting for movement
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationPermission();
    });

    // Subscribe to LocationService so debug values refresh on every GPS ping
    LocationService.instance.addListener(_onLocationUpdate);
    ShiftTrackingService.instance.addListener(_onShiftUpdate);

    _loadDashboardData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRunRiskIdentityReview();
    });
    _disruptionRefreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (!mounted) return;
      _loadDashboardData();
    });

    _policySub = AppEvents.instance.onPolicyUpdated.listen((_) async {
      await _loadDashboardData();
    });
    // Debounced: only reload wallet/claim data at most once every 5 seconds
    _walletSub = AppEvents.instance.onWalletUpdated.listen((_) {
      _loadDashboardData();
    });
    _claimSub = AppEvents.instance.onClaimUpdated.listen((_) {
      _loadDashboardData();
    });

    AppEvents.instance.onProfileUpdated.listen((_) {
      if (mounted) _loadDashboardData();
    });
  }

  /// Get a one-shot GPS fix immediately on mount so the debug panel shows
  /// real coordinates without requiring the user to physically move first.
  Future<void> _fetchInitialLocation() async {
    try {
      if (kIsWeb) {
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) {
          p = await Geolocator.requestPermission();
        }
        if (p == LocationPermission.denied ||
            p == LocationPermission.deniedForever) {
          return;
        }
      } else {
        final hasPermission = await Permission.locationWhenInUse.isGranted;
        if (!hasPermission) return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      LocationService.instance.updateFromGps(pos.latitude, pos.longitude);
      if (mounted) setState(() {});
    } catch (_) {
      // Silently skip if GPS unavailable
    }
  }

  /// Run a live health check against each key API endpoint and store results.
  bool _isMLFetching = false;
  Future<void> _fetchLiveMLData(String tier) async {
    if (!mounted || !_enableLiveML) return;
    setState(() => _isMLFetching = true);
    try {
      final issData = await ApiService.instance.getIssScore();
      if (!mounted) return;
      final score = issData['iss_score'] as int?;
      if (score != null) {
        liveIssScore = score;
        final premData =
            await ApiService.instance.getDynamicPremium(tier, score);
        if (mounted) {
          setState(() {
            liveDynamicPrice = (premData['final_premium'] as num?)?.toDouble();
            _isMLFetching = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isMLFetching = false);
    }
  }

  void _checkApiHealth() async {
    setState(() => _apiHealthStatus = {'_loading': 'true'});
    final base = ApiService.baseUrl;
    final results = <String, String>{};

    Future<String> ping(String path) async {
      try {
        final res = await http
            .get(
              Uri.parse('$base$path'),
            )
            .timeout(const Duration(seconds: 8));
        return res.statusCode < 400
            ? '✅ ${res.statusCode}'
            : '❌ ${res.statusCode}';
      } on TimeoutException {
        return '⏱ TIMEOUT';
      } catch (e) {
        return '❌ ERR';
      }
    }

    results['GET /health'] = await ping('/health');
    if (userId != null) {
      results['GET /workers/:id'] = await ping('/workers/$userId');
      results['GET /policies/:id'] = await ping('/policies/$userId');
      results['GET /wallet/:id'] = await ping('/wallet/$userId');
      results['GET /claims/:id'] = await ping('/claims/$userId');
      final zone = Uri.encodeComponent(userZone ?? '');
      results['GET /disruptions'] = await ping('/disruptions/$zone');
    } else {
      results['NOTE'] = 'Log in first for user-scoped endpoints';
    }

    if (mounted) setState(() => _apiHealthStatus = results);
  }

  Future<void> _checkLocationPermission() async {
    // Skip permission checks on web - permission_handler not supported
    if (kIsWeb) {
      setState(() {
        _locationPermissionStatus = 'GRANTED';
        _backgroundTrackingActive = false;
      });
      return;
    }

    final status = await Permission.locationWhenInUse.status;
    final bgStatus = await Permission.locationAlways.status;
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();

    if (mounted) {
      setState(() {
        if (!gpsEnabled) {
          _locationPermissionStatus = 'GPS_DISABLED_ON_DEVICE';
        } else {
          _locationPermissionStatus = status.toString();
        }
        _backgroundTrackingActive = bgStatus.isGranted && gpsEnabled;
      });
    }
  }

  Future<void> _maybeRunRiskIdentityReview() async {
    if (!mounted || _reverifyPromptOpen) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastRiskReview = StorageService.getInt('lastRiskReviewAt') ?? 0;
    const minGapMs = 15 * 60 * 1000; // do not recheck too frequently
    if (now - lastRiskReview < minGapMs) return;
    // Note: write the timestamp only after we decide to actually challenge,
    // so an early unmount doesn't consume the 15-min window.

    final hasEnrollment =
        await StorageService.instance.isIdentityEnrollmentComplete();
    if (!mounted) return; // guard: widget may unmount during storage read
    bool shouldChallenge = !hasEnrollment;
    bool isRiskTriggered = false;

    if (!shouldChallenge) {
      try {
        final sensor = await FraudSensorService.collectPayload();
        if (!mounted) return; // guard: GPS sampling takes 1–2 seconds
        final ml = await ApiService.instance.validateFraudTelemetry(sensor);
        if (!mounted) return; // guard: network call
        final anomalous = ml['is_anomalous'] == true;
        final fps = (ml['fps_score'] as num?)?.toDouble() ?? 0.0;
        isRiskTriggered = anomalous || fps >= 0.75;
      } catch (_) {
        isRiskTriggered = false;
      }
      final randomAudit = math.Random().nextInt(100) < 3; // 3% random checks
      shouldChallenge = isRiskTriggered || randomAudit;
    }

    if (!shouldChallenge || !mounted) return;

    // Commit the review timestamp only now that we are actually challenging
    await StorageService.setLastRiskReviewAt(now);
    if (!mounted) return;

    _reverifyPromptOpen = true;
    final reason = Uri.encodeComponent(
      !hasEnrollment
          ? 'Complete first-time identity enrollment to secure your account.'
          : (isRiskTriggered
              ? 'Suspicious account activity detected. Re-verify your identity to continue.'
              : 'Quick security check: please re-verify your identity.'),
    );
    final requireTwoTier = !hasEnrollment;
    // Use the global appRouter instead of context.push — avoids stale context
    // crash when the widget tree switches (e.g. shift going active mid-await)
    final result = await appRouter.push<Map<String, dynamic>>(
      '${AppRoutes.stepUpAuth}?reason=$reason&requireTwoTier=$requireTwoTier',
    );
    _reverifyPromptOpen = false;

    if (!mounted) return;
    if (result != null && result['verified'] == true) {
      await StorageService.instance.markIdentityVerifiedNow();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Identity verification was not completed.'),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheckAllPermissions();
      _checkLocationPermission();
      // Re-fetch data in case user just granted permissions (location etc.)
      // or the app was backgrounded while data was loading.
      if (!_isDashboardLoading) {
        _loadDashboardData();
      }
    }
  }

  Future<void> _recheckAllPermissions() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _backgroundTrackingActive = false;
          _locationPermissionStatus = 'GRANTED';
        });
      }
      return;
    }

    final locationPerm = await Geolocator.checkPermission();

    if (mounted) {
      setState(() {
        _backgroundTrackingActive = locationPerm == LocationPermission.always;
        _locationPermissionStatus = locationPerm.toString();
      });
    }
  }

  int _lastLocUpdate = 0;
  void _onLocationUpdate() {
    if (!mounted) return;

    final newZone = LocationService.instance.currentZone;
    if (newZone != "Unknown Zone" &&
        newZone != "Outside Service Area" &&
        newZone != userZone) {
      final zoneShort = newZone.split(' ').first;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📍 Location Verified: Entering $zoneShort Hub'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      setState(() {
        userZone = newZone;
      });
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastLocUpdate > 5000) {
      // Every 5 seconds max
      _lastLocUpdate = now;
      setState(() {});
    }
  }

  int _lastShiftUpdate = 0;
  void _onShiftUpdate() {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastShiftUpdate > 5000) {
      // Every 5 seconds max
      _lastShiftUpdate = now;
      setState(() {});
    }
  }

  @override
  void dispose() {
    LocationService.instance.removeListener(_onLocationUpdate);
    ShiftTrackingService.instance.removeListener(_onShiftUpdate);
    WidgetsBinding.instance.removeObserver(this);
    _disruptionRefreshTimer?.cancel();
    _locationStream?.cancel();
    _policySub?.cancel();
    _walletSub?.cancel();
    _claimSub?.cancel();
    super.dispose();
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  Future<bool> _restoreDashboardFromCache() async {
    try {
      final raw = StorageService.getString(_dashboardSnapshotKey);
      if (raw == null || raw.isEmpty) return false;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final snapshot = Map<String, dynamic>.from(decoded);

      final cachedPolicy = _asMap(snapshot['policyData']);
      final cachedWallet = _asMap(snapshot['walletData']);
      final cachedDisruption = _asMap(snapshot['disruptionData']);
      final cachedWeather = _asMap(snapshot['weatherData']);
      final cachedNudge = _asMap(snapshot['nudgeData']);
      final cachedAdvisor = _asMap(snapshot['workAdvisorData']);
      final cachedActive = _asMap(snapshot['activeDisruption']);

      if (!mounted) return false;
      setState(() {
        policyData = cachedPolicy;
        walletData = cachedWallet;
        disruptionData = cachedDisruption;
        weatherData = cachedWeather;
        nudgeData = cachedNudge;
        workAdvisorData = cachedAdvisor;
        activeDisruption = cachedActive;

        final cachedZone = snapshot['userZone']?.toString();
        final cachedName = snapshot['userName']?.toString();
        if (cachedZone != null && cachedZone.isNotEmpty) userZone = cachedZone;
        if (cachedName != null && cachedName.isNotEmpty) userName = cachedName;

        final cachedIss = snapshot['liveIssScore'];
        if (cachedIss is num) liveIssScore = cachedIss.toInt();
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistDashboardSnapshot() async {
    try {
      final snapshot = <String, dynamic>{
        'policyData': policyData,
        'walletData': walletData,
        'disruptionData': disruptionData,
        'weatherData': weatherData,
        'nudgeData': nudgeData,
        'workAdvisorData': workAdvisorData,
        'activeDisruption': activeDisruption,
        'userZone': userZone,
        'userName': userName,
        'liveIssScore': liveIssScore,
        'cachedAt': DateTime.now().toIso8601String(),
      };
      await StorageService.setString(
        _dashboardSnapshotKey,
        jsonEncode(snapshot),
      );
    } catch (_) {
      // Best-effort cache; skip on serialization/storage failure.
    }
  }

  Future<void> _refreshWorkerIss(String uid) async {
    try {
      final worker = await ApiService.instance.getWorkerById(uid);
      final rawIss = worker['iss_score'];
      if (rawIss is num && mounted) {
        setState(() => liveIssScore = rawIss.round().clamp(0, 100));
      }
    } catch (_) {
      // ISS is non-critical for first paint; ignore transient failures.
    }
  }

  Future<void> _loadDashboardData() async {
    // Prevent concurrent API call stacks from piling up
    if (_isDashboardLoading) return;
    _isDashboardLoading = true;

    // Render cached snapshot first (if available) to reduce perceived load time.
    if (isLoading) {
      await _restoreDashboardFromCache();
    }

    final userMeta = await Future.wait<dynamic>([
      StorageService.instance.getUserId(),
      StorageService.instance.getUserZone(),
      StorageService.instance.getUserName(),
    ]);
    userId = userMeta[0] as String?;
    userZone = userMeta[1] as String?;
    userName = userMeta[2] as String?;

    // ── Demo Consistency Guard ───────────────────────────────────────────
    final mockSvc = Provider.of<MockDataService>(context, listen: false);
    final isDemoMode = StorageService.getString('isDemoSession') == 'true';
    final isMockUser = mockSvc.worker.id.startsWith('DEMO_') ||
        mockSvc.worker.id.startsWith('demo-') ||
        mockSvc.worker.id.startsWith('mock-') ||
        mockSvc.worker.id.startsWith('00000000') ||
        userId?.startsWith('00000000') == true ||
        userId?.startsWith('demo-') == true ||
        userId?.startsWith('mock-') == true ||
        isDemoMode;

    if (isMockUser) {
      Map<String, dynamic> weatherFallback = {
        'source': 'Live System',
        'rainfall_mm_1h':
            mockSvc.activeDisruption?.triggerIcon == 'rain' ? 72.4 : 0.0,
        'temp_celsius':
            mockSvc.activeDisruption?.triggerIcon == 'heat' ? 42.0 : 29.0,
      };

      // Fetch live API weather without blocking the dashboard render
      unawaited(() async {
        try {
          final liveDisruptions =
              await ApiService.instance.getDisruptions(userZone ?? '');
          final liveWeather =
              liveDisruptions['weather'] as Map<String, dynamic>? ?? {};
          final apiRain =
              (liveWeather['rainfall_mm_1h'] as num?)?.toDouble() ?? 0.0;
          final apiTemp =
              (liveWeather['temp_celsius'] as num?)?.toDouble() ?? 29.0;
          final apiNudge = liveDisruptions['predictive_nudge'] as Map<String, dynamic>?;

          if (mounted) {
            setState(() {
              if (apiNudge != null) {
                nudgeData = {
                  'nudge_date': apiNudge['date'],
                  'probability_percentage': apiNudge['rain_chance'],
                  'description': apiNudge['message'] ?? apiNudge['description'],
                  'simulated_payout': apiNudge['expected_payout'] ?? 360,
                };
              } else {
                nudgeData = {
                  'nudge_date': 'Friday',
                  'probability_percentage': 85,
                  'description': 'Heavy rain expected in your zone.',
                  'simulated_payout': 360,
                };
              }
              weatherData = {
                'source': 'Live API',
                'rainfall_mm_1h':
                    mockSvc.activeDisruption?.triggerIcon == 'rain'
                        ? 72.4
                        : apiRain,
                'temp_celsius': mockSvc.activeDisruption?.triggerIcon == 'heat'
                    ? 42.0
                    : apiTemp,
              };
            });
          }
        } catch (_) {}
      }());

      if (mounted) {
        setState(() {
          userId = mockSvc.worker.id;
          userName = mockSvc.worker.name;
          userZone = mockSvc.worker.zone;

          // Check MockDataService first, then fall back to local StorageService
          // (covers real purchases that write to StorageService, not demo_hasActivePolicy).
          final storedPolicyId = StorageService.policyId;
          final hasAnyPolicy =
              mockSvc.hasActivePolicy || storedPolicyId.isNotEmpty;
          if (hasAnyPolicy) {
            final tier = mockSvc.hasActivePolicy
                ? mockSvc.activePolicy.plan.split(' ')[0].toLowerCase()
                : (StorageService.getString('activePlanTier') ?? 'standard');
            final planName = mockSvc.hasActivePolicy
                ? mockSvc.activePolicy.plan
                : (StorageService.getString('activePlanName') ??
                    'Standard Shield');
            final premium = mockSvc.hasActivePolicy
                ? mockSvc.activePolicy.premium
                : (StorageService.getInt('weeklyPremium') ?? 49);
            policyData = {
              'id': storedPolicyId.isNotEmpty
                  ? storedPolicyId
                  : 'PROTO-POL-${mockSvc.worker.id.hashCode}',
              'plan_tier': tier,
              'plan_name': planName,
              'status': 'active',
              'weekly_premium': premium,
              'coverage_start': mockSvc.hasActivePolicy
                  ? mockSvc.activePolicy.coverageStart
                  : '',
              'commitment_end': mockSvc.hasActivePolicy
                  ? mockSvc.activePolicy.coverageEnd
                  : '',
            };
          } else {
            policyData = null;
          }

          walletData = {
            'balance': mockSvc.walletBalance,
            'total_payouts': mockSvc.monthlySavings,
            'total_premiums': mockSvc.totalPremiums,
            'transactions': mockSvc.transactions,
          };

          if (mockSvc.activeDisruption != null) {
            final active = mockSvc.activeDisruption!;
            activeDisruption = {
              'display_name': active.triggerName,
              'trigger_type': active.triggerIcon,
            };
            disruptionData = {
              'active': true,
              'trigger_type': active.triggerName,
              'zone': userZone,
            };
          } else {
            activeDisruption = null;
            disruptionData = const {'active': false};
          }

          weatherData = weatherFallback;

          liveIssScore = mockSvc.worker.issScore;
          final iss = liveIssScore ?? 62;

          // Construct rich ESI Work Advisor data driven by actual ISS score
          String bandLabel, headline, nudge;
          List<Map<String, dynamic>> shiftWindows;
          bool suggestCoverage;

          if (iss >= 80) {
            bandLabel = 'High Stability';
            headline =
                'Your earnings are consistent, but sudden weather changes could still disrupt your peak windows.';
            nudge =
                'Protect your strong run — even high earners face unexpected disruptions.';
            suggestCoverage = false;
            shiftWindows = [
              {'label': 'Morning', 'time': '7 AM – 11 AM', 'demand': 'High'},
              {'label': 'Evening', 'time': '6 PM – 9 PM', 'demand': 'Peak'},
            ];
          } else if (iss >= 60) {
            bandLabel = 'Moderate Stability';
            headline =
                'There is a moderate chance of weather or platform issues coming up that might dip your earnings.';
            final projectedWeeklyImpact = mockSvc.potentialLoss.clamp(80, 250);
            nudge =
                'An upcoming disruption could cost you up to ₹$projectedWeeklyImpact this week. '
                'A ₹${mockSvc.activePolicy.premium}/week plan helps cover that risk.';
            suggestCoverage = true;
            shiftWindows = [
              {
                'label': 'Late Morning',
                'time': '10 AM – 1 PM',
                'demand': 'Medium'
              },
              {'label': 'Evening', 'time': '5 PM – 8 PM', 'demand': 'High'},
            ];
          } else {
            bandLabel = 'Low Stability';
            headline =
                'High chances of severe weather or outages coming up in your zone. Your earnings are at risk.';
            nudge =
                'You missed ₹${mockSvc.missedAmount} in recent events. Don\'t lose out again. Coverage starts at ₹35/week.';
            suggestCoverage = true;
            shiftWindows = [
              {
                'label': 'Mid-morning',
                'time': '9 AM – 12 PM',
                'demand': 'Medium'
              },
              {'label': 'Evening', 'time': '6 PM – 9 PM', 'demand': 'High'},
            ];
          }

          workAdvisorData = {
            'earning_stability_index': iss,
            'stability_band_label': bandLabel,
            'headline': headline,
            'coverage_nudge': nudge,
            'suggest_activate_coverage': suggestCoverage,
            'recommended_shift_windows': shiftWindows,
          };

          // If no active disruption and no policy, also clear any stale nudge
          if (mockSvc.activeDisruption == null) {
            nudgeData = null;
          }

          isLoading = false;
        });
      }

      // ── Live API Blend (detached) ────────────────────────────────────────
      // Fetch real weather + ML ISS for the persona's zone so the dashboard
      // shows BOTH live conditions AND mock claims/disruptions simultaneously.
      // This runs after the mock data has already painted the UI, so there's
      // no perceived lag.
      unawaited(() async {
        try {
          final zone = mockSvc.spoofedZone ?? mockSvc.worker.zone;
          final liveDisruptions = await ApiService.instance.getDisruptions(zone);
          final liveWeather = liveDisruptions['weather'] as Map<String, dynamic>? ?? {};
          final liveNudge = liveDisruptions['predictive_nudge'] as Map<String, dynamic>?;
          final apiRain = (liveWeather['rainfall_mm_1h'] as num?)?.toDouble() ?? 0.0;
          final apiTemp = (liveWeather['temp_celsius'] as num?)?.toDouble() ?? 29.0;
          final apiSource = liveWeather['source']?.toString() ?? 'Live API';

          // Fetch real ML ISS score for the zone/persona
          int? liveIss;
          try {
            final issData = await ApiService.instance.getIssScore();
            liveIss = (issData['iss_score'] as num?)?.toInt();
          } catch (_) {}

          if (!mounted) return;
          setState(() {
            // Blend: weather is always real API (most accurate)
            // but mock disruption overlay/trigger OVERRIDES rain reading
            final hasRainDisruption = mockSvc.activeDisruption?.triggerIcon == 'rain';
            final hasHeatDisruption = mockSvc.activeDisruption?.triggerIcon == 'heat';
            weatherData = {
              'source': '$apiSource + Mock Overlay',
              'rainfall_mm_1h': hasRainDisruption ? 72.4 : apiRain,
              'temp_celsius': hasHeatDisruption ? 42.0 : apiTemp,
              // Preserve any extra real-API fields
              ...liveWeather,
              // Always label it as a blend so the debug panel is honest
              'source': '$apiSource + Mock',
            };
            // Update ISS with real score if mock hasn't explicitly set one
            if (liveIss != null) {
              liveIssScore = liveIss;
            }
            // Merge live nudge with mock but only if no mock disruption is overriding
            if (liveNudge != null && mockSvc.activeDisruption == null) {
              nudgeData = {
                'nudge_date': liveNudge['date'],
                'probability_percentage': liveNudge['rain_chance'],
                'description': liveNudge['message'] ?? liveNudge['description'],
                'simulated_payout': liveNudge['expected_payout'] ?? 360,
              };
            }
          });
        } catch (_) {
          // Non-critical: live API fetch failed, mock data already displayed
        }
      }());

      unawaited(_persistDashboardSnapshot());
      _isDashboardLoading = false;
      return;
    }

    if (userId == null) {
      _isDashboardLoading = false;
      if (mounted) setState(() => isLoading = false);
      return;
    }

    try {
      final dashboardCore = await Future.wait<dynamic>([
        ApiService.instance.getPolicy(userId!),
        ApiService.instance.getWallet(userId!),
        ApiService.instance.getDisruptions(userZone ?? ''),
      ]);

      final policyRes = dashboardCore[0] as Map<String, dynamic>;
      final walletRes = dashboardCore[1] as Map<String, dynamic>;
      final disruptionRes = dashboardCore[2] as Map<String, dynamic>;

      // Fetch ISS after first paint to avoid delaying dashboard load.
      unawaited(_refreshWorkerIss(userId!));

      final rawPolicy = policyRes['policy'] as Map<String, dynamic>?;
      final tier = rawPolicy?['plan_tier'] as String?;

      // Support new schema field names: coverage_start / commitment_end
      final policyWithAliases = rawPolicy == null
          ? null
          : {
              ...rawPolicy,
              // Ensure start_date / end_date are always populated for legacy code paths.
              if (!rawPolicy.containsKey('start_date'))
                'start_date': rawPolicy['coverage_start'],
              if (!rawPolicy.containsKey('end_date'))
                'end_date':
                    rawPolicy['commitment_end'] ?? rawPolicy['paid_until'],
              'plan_name': _planDisplayName(tier),
            };

      // Gate: only show policyData if status is active or renewed
      final rawStatus = rawPolicy?['status']?.toString().toLowerCase() ?? '';
      final isPolicyActive = rawStatus == 'active' || rawStatus == 'renewed';
      final hasValidTier = tier != null && tier.trim().isNotEmpty;

      // Real users should only see active policy when backend confirms it.
      policyData = isPolicyActive && hasValidTier ? policyWithAliases : null;

      // WALLET FALLBACK: If user is a demo user, prioritize MockDataService wallet
      final isDemoUser = userId?.startsWith('DEMO_') == true ||
          userId?.startsWith('demo-') == true ||
          userId?.startsWith('mock-') == true ||
          StorageService.getString('isDemoSession') == 'true';
      if (isDemoUser) {
        walletData = {
          'balance': mockSvc.walletBalance.toInt(),
          'total_payouts': mockSvc.monthlySavings.toInt(),
          'total_premiums': 0,
          'transactions': mockSvc.transactions,
        };
      } else {
        walletData = walletRes;
      }

      final events = disruptionRes['disruptions'] as List<dynamic>? ?? [];
      final active = disruptionRes['active'] == true;
      final rawWeather = disruptionRes['weather'] as Map<String, dynamic>?;
      final rawDataSources =
          disruptionRes['data_sources'] as Map<String, dynamic>?;
      final rawNudge =
          disruptionRes['predictive_nudge'] as Map<String, dynamic>?;
      final rawAdvisor = disruptionRes['work_advisor'] as Map<String, dynamic>?;

      Map<String, dynamic>? latestDisruption;
      if (!active || events.isEmpty) {
        disruptionData = const {'active': false};
      } else {
        latestDisruption = events.first as Map<String, dynamic>;
        disruptionData = {
          'active': true,
          'trigger_type': latestDisruption['display_name'] as String? ??
              _disruptionTriggerLabel(
                  latestDisruption['trigger_type'] as String?),
          'zone': userZone ?? 'Your Zone',
        };
      }

      // Normalize weather payload so source is never null in UI/debug views.
      final normalizedWeather = <String, dynamic>{
        ...?rawWeather,
      };
      final bundleWeatherSource = rawDataSources?['weather']?.toString().trim();
      final rawSource = normalizedWeather['source']?.toString().trim();
      final rawStation = normalizedWeather['station']?.toString().trim();
      final rawProvider = normalizedWeather['provider']?.toString().trim();
      final hasSource = rawSource != null &&
          rawSource.isNotEmpty &&
          rawSource.toLowerCase() != 'null';
      if (!hasSource) {
        normalizedWeather['source'] = (bundleWeatherSource != null &&
                bundleWeatherSource.isNotEmpty &&
                bundleWeatherSource.toLowerCase() != 'null')
            ? bundleWeatherSource
            : (rawStation != null &&
                    rawStation.isNotEmpty &&
                    rawStation.toLowerCase() != 'null')
                ? rawStation
                : (rawProvider != null &&
                        rawProvider.isNotEmpty &&
                        rawProvider.toLowerCase() != 'null')
                    ? rawProvider
                    : active
                        ? 'Disruption Engine'
                        : 'Live API';
      }

      // The dashboard data has landed! Render it instantly.
      if (mounted) {
        setState(() {
          weatherData = normalizedWeather;
          activeDisruption = latestDisruption;
          // Sync backend keys (date, rain_chance, message) to frontend expected keys (nudge_date, etc)
          if (rawNudge != null) {
            nudgeData = {
              'nudge_date': rawNudge['date'],
              'probability_percentage': rawNudge['rain_chance'],
              'description': rawNudge['message'] ?? rawNudge['description'],
              'simulated_payout': rawNudge['expected_payout'] ?? 360,
            };
          } else {
            nudgeData = null;
          }
          workAdvisorData = rawAdvisor;
          isLoading = false;
        });
      }
      unawaited(_persistDashboardSnapshot());

      // ── Organic ML Data Fetch (Detached Background Task) ──
      // This prevents the app from freezing if Render is experiencing a cold start.
      _fetchLiveMLData(tier ?? 'standard');

      // Trigger notifications based on policy status and disruptions
      final hasActivePolicy = policyData != null;
      final hasDisruptions = events.isNotEmpty;

      // Only fire notifications for genuinely new data — not every load
      // Rain alert: only when disruption is truly active (server-confirmed)
      if (hasDisruptions && active && hasActivePolicy) {
        NotificationService.instance.addRainAlert(userZone ?? 'your zone');
      }
      // Missed payout: only for users WITHOUT a policy AND confirmed disruptions
      if (hasDisruptions && active && !hasActivePolicy) {
        NotificationService.instance.addMissedPayout(350);
      }

      // ── Rapido-style disruption overlay (workers online with active policy) ──
      if (active && hasActivePolicy && hasDisruptions && mounted) {
        final disruptionId = latestDisruption?['id']?.toString() ??
            latestDisruption?['trigger_type']?.toString() ??
            'disruption_${DateTime.now().day}';
        _maybeShowDisruptionOverlay(
          disruptionId: disruptionId,
          triggerType: latestDisruption?['trigger_type']?.toString() ?? 'rain',
          zone: userZone ?? 'Your Zone',
        );
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    } finally {
      _isDashboardLoading = false;
    }
  }

  /// Show the disruption overlay — but only once per unique disruption ID
  /// and only when the worker is actively online.
  void _maybeShowDisruptionOverlay({
    required String disruptionId,
    required String triggerType,
    required String zone,
  }) {
    if (_disruptionOverlayOpen) return;
    if (_lastShownDisruptionId == disruptionId) return;
    if (ShiftTrackingService.instance.status != ShiftStatus.active) return;
    if (!mounted) return;

    _lastShownDisruptionId = disruptionId;
    _disruptionOverlayOpen = true;

    // Estimate payout based on plan tier
    final tier =
        (policyData?['plan_tier'] as String? ?? 'standard').toLowerCase();
    final payout =
        tier.contains('full') ? 300 : (tier.contains('basic') ? 150 : 220);

    DisruptionAlertOverlay.show(
      context,
      triggerType: triggerType,
      zone: zone,
      estimatedPayout: payout,
    ).whenComplete(() {
      if (mounted) setState(() => _disruptionOverlayOpen = false);
    });
  }

  static String _planDisplayName(String? tier) {
    if (tier == null || tier.trim().isEmpty) return 'No Active Plan';
    const m = {
      'basic': 'Basic Shield',
      'standard': 'Standard Shield',
      'full': 'Full Shield',
    };
    return m[tier] ?? 'No Active Plan';
  }

  static String _disruptionTriggerLabel(String? t) {
    const labels = {
      'rain_heavy': 'Heavy Rain',
      'platform_outage': 'Platform Downtime',
      'heat_severe': 'Extreme Heat',
      'extreme_heat': 'Extreme Heat',
      'bandh': 'Bandh / Curfew',
      'aqi_severe': 'Severe Pollution',
      'aqi_hazardous': 'Severe Pollution',
    };
    if (t == null) return 'Rain';
    return labels[t] ??
        (t.isNotEmpty
            ? '${t[0].toUpperCase()}${t.substring(1).replaceAll('_', ' ')}'
            : 'Rain');
  }

  static String _planNameWithRiders(Map<String, dynamic> policy) {
    final base = (policy['plan_name']?.toString().trim().isNotEmpty ?? false)
        ? policy['plan_name'].toString().trim()
        : _planDisplayName(policy['plan_tier']?.toString().toLowerCase());

    final riders = policy['riders'] as List<dynamic>?;
    if (riders == null || riders.isEmpty) return base;

    final riderNames = riders
        .whereType<Map>()
        .map((r) => r['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    if (riderNames.isEmpty) return base;
    return '$base + ${riderNames.join(' + ')}';
  }

  static int _resolveWeeklyPremium(Map<String, dynamic> policy) {
    final raw = policy['weekly_premium'];
    if (raw is num && raw > 0) return raw.round();
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed != null && parsed > 0) return parsed;
    return PlanTierPrice.fromString(
      policy['plan_tier']?.toString().toLowerCase() ?? 'standard',
    ).weeklyPremium;
  }

  static String _formatPolicyNumber(Map<String, dynamic> policy) {
    final explicit = policy['policy_number']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final id = policy['id']?.toString().trim();
    if (id == null || id.isEmpty) return 'HS-PENDING';
    final compact = id.replaceAll('-', '').toUpperCase();
    final suffix = compact.length >= 8 ? compact.substring(0, 8) : compact;
    return 'HS-$suffix';
  }

  String _getGreetingText(BuildContext context) {
    final h = DateTime.now().hour;
    final l10n = AppLocalizations.of(context)!;
    if (h < 12) return l10n.dashboard_greeting_morning;
    if (h < 17) return l10n.dashboard_greeting_afternoon;
    return l10n.dashboard_greeting_evening;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    if (isLoading) {
      return _buildDashboardSkeleton();
    }

    final isLocationDenied =
        _locationPermissionStatus.contains('permanentlyDenied');
    final isGpsOff = _locationPermissionStatus == 'GPS_DISABLED_ON_DEVICE';

    final hasActivePolicy = policyData != null;
    final rawPlanName = hasActivePolicy
        ? (policyData!['plan_name']?.toString() ?? 'No Active Plan')
        : 'No Active Plan';
    final List<dynamic>? ridersData = policyData?['riders'];
    String planName = rawPlanName;
    if (ridersData != null && ridersData.isNotEmpty) {
      final names = ridersData.map((r) => r['name'].toString()).join(' + ');
      planName = '$rawPlanName + $names';
    }

    String titleCase(String text) {
      if (text.isEmpty) return text;
      return text.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }

    final displayUserName = titleCase(userName ?? 'Karthik');

    final planTier = hasActivePolicy
        ? policyData!['plan_tier']?.toString().toLowerCase() ?? 'standard'
        : '';
    final tierBasePremium =
        hasActivePolicy ? PlanTierPrice.fromString(planTier).weeklyPremium : 0;

    int riderCostFromName(String name) {
      final n = name.toLowerCase();
      if (n.contains('cyclone')) return 20;
      if (n.contains('curfew') || n.contains('strike')) return 12;
      if (n.contains('election')) return 8;
      if (n.contains('app downtime') || n.contains('downtime')) return 10;
      return 0;
    }

    bool isIncludedInPlan(String riderName) {
      final n = riderName.toLowerCase();
      if (planTier == 'full') return true;
      if (planTier == 'standard' &&
          (n.contains('app downtime') || n.contains('downtime'))) {
        return true;
      }
      return false;
    }

    int billableAddonTotal = 0;
    if (ridersData != null) {
      for (final r in ridersData) {
        if (r is! Map) continue;
        final name = r['name']?.toString() ?? '';
        if (name.isEmpty || isIncludedInPlan(name)) continue;

        final explicitCost = (r['cost'] as num?)?.toInt();
        final resolvedCost = (explicitCost != null && explicitCost > 0)
            ? explicitCost
            : riderCostFromName(name);
        billableAddonTotal += resolvedCost;
      }
    }

    final computedTotalPremium = tierBasePremium + billableAddonTotal;

    // Prefer valid backend-stored weekly premium, but ensure we never under-show
    // when billable add-ons exist (base + add-ons must be reflected).
    final rawWeeklyPremium = (policyData?['weekly_premium'] is num)
        ? (policyData?['weekly_premium'] as num).toDouble()
        : double.tryParse(policyData?['weekly_premium']?.toString() ?? '');
    final normalizedPremium = (rawWeeklyPremium != null &&
            rawWeeklyPremium >= computedTotalPremium &&
            rawWeeklyPremium <= 200)
        ? rawWeeklyPremium.round().toString()
        : computedTotalPremium.toString();

    final String premium = (liveDynamicPrice != null && billableAddonTotal == 0)
        ? liveDynamicPrice!.toStringAsFixed(0)
        : normalizedPremium;

    // Derive missed-payout amount from shadow_policies nudge data (real DB field),
    // then fall back to a disruption-based estimate — never reads a non-existent field.
    final mockSvc = Provider.of<MockDataService>(context, listen: false);
    final shadowPayout = (nudgeData?['simulated_payout'] as num?)?.toInt() ??
        (nudgeData?['missed_amount'] as num?)?.toInt();
    final disruptionCount =
        ((nudgeData?['disruption_count'] as num?)?.toInt() ?? 0);

    // DEMO SYNC: If in demo mode, prioritize mockSvc.missedAmount
    final isDemoMode =
        userId?.startsWith('DEMO_') == true ||
        userId?.startsWith('demo-') == true ||
        userId?.startsWith('mock-') == true ||
        StorageService.getString('isDemoSession') == 'true';

    final pAmount = isDemoMode
        ? mockSvc.missedAmount
        : (shadowPayout ?? (disruptionCount > 0 ? disruptionCount * 120 : 350));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              color: const Color(0xFF10B981),
              backgroundColor: const Color(0xFF161B22),
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 24),
                physics: const AlwaysScrollableScrollPhysics(),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      const OfflineBanner(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(context, displayUserName),
                            const SizedBox(height: 16),
                            _buildTitleSection(l10n, displayUserName),
                            // ── Go Online ── shown prominently at top so users never miss it
                            if (ShiftTrackingService.instance.status == ShiftStatus.offline) ...[
                              const SizedBox(height: 16),
                              BatteryOptimizationPrompt(onAllGranted: () async {
                                if (_isGoingOnline || ShiftTrackingService.instance.status != ShiftStatus.offline) return;
                                setState(() => _isGoingOnline = true);
                                if (kIsWeb) {
                                  try {
                                    final zone = userZone?.isNotEmpty == true ? userZone! : 'Local Zone';
                                    await ShiftTrackingService.instance.startShift(zone);
                                    AppEvents.instance.profileUpdated();
                                  } catch (e) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not go online on web: $e')));
                                  } finally {
                                    if (mounted) setState(() => _isGoingOnline = false);
                                  }
                                  return;
                                }
                                try {
                                  final gpsEnabled = await Geolocator.isLocationServiceEnabled();
                                  if (!gpsEnabled) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please turn on device location to go online')));
                                    setState(() => _isGoingOnline = false);
                                    return;
                                  }
                                  try {
                                    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).timeout(const Duration(seconds: 15));
                                    await StorageService.instance.setLastLat(position.latitude);
                                    await StorageService.instance.setLastLng(position.longitude);
                                  } catch (gpsError) {
                                    print('[GoOnline] GPS timeout: $gpsError — using last known');
                                  }
                                  final zone = userZone?.isNotEmpty == true ? userZone! : 'Local Zone';
                                  await ShiftTrackingService.instance.startShift(zone);
                                  AppEvents.instance.profileUpdated();
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are online.'), duration: Duration(seconds: 2)));
                                } catch (e) {
                                  print('[GoOnline] ERROR: $e');
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not go online: $e')));
                                } finally {
                                  if (mounted) setState(() => _isGoingOnline = false);
                                }
                              }),
                            ],
                            const SizedBox(height: 20),
                            if (isLocationDenied || isGpsOff) ...[
                              _buildLocationStatusBanner(context,
                                  isGpsOff: isGpsOff),
                              const SizedBox(height: 16),
                            ],
                            if (nudgeData != null) ...[
                              _buildPredictiveNudgeCard(l10n),
                              const SizedBox(height: 16),
                            ],
                            _buildRainAlertCard(l10n),
                            if (workAdvisorData != null) ...[
                              const SizedBox(height: 16),
                              _buildWorkAdvisorCard(),
                            ],
                            const SizedBox(height: 20),
                            if (policyData != null)
                              _buildActivePolicyCard(
                                planName,
                                premium,
                                l10n,
                                ridersData,
                                policyData?['plan_tier']?.toString() ??
                                    'standard',
                              )
                            else
                              _buildNoPolicyCard(l10n),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF121512)
                                    : const Color(0xFFF7FAF7),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : const Color(0xFF1B5E20)
                                          .withValues(alpha: 0.08),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDark
                                        ? Colors.black.withValues(alpha: 0.18)
                                        : const Color(0xFF1B5E20)
                                            .withValues(alpha: 0.05),
                                    blurRadius: 24,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  _buildActionCards(context, l10n),
                                  // Show missed-payouts card only for UNINSURED users
                                  // so it serves as a conversion nudge, not a bug.
                                  if (policyData == null) ...[
                                    const SizedBox(height: 16),
                                    _buildMissedPayoutsCard(
                                        pAmount, context, l10n),
                                  ],
                                ],
                              ),
                            ),
                            if (_debugMode) _buildDebugPanel(),
                          ],
                        ),
                      ),
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

  Widget _buildHeader(BuildContext context, String displayUserName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mintColor =
        isDark ? const Color(0xFF3fff8b) : const Color(0xFF1B5E20);

    return Row(
      children: [
        GestureDetector(
          onTap: () => context.push(AppRoutes.profile),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: mintColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: mintColor, width: 2),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.person, color: mintColor, size: 28),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          displayUserName, // passed in
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
            fontFamily: 'Manrope',
          ),
        ),
        const SizedBox(width: 8),
        const ShiftStatusDot(),
        const SizedBox(width: 8),
        // Live Tracker Pill
        if (LocationService.instance.traveledDistance > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: mintColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: mintColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded, size: 12, color: mintColor),
                const SizedBox(width: 4),
                Text(
                  '${LocationService.instance.traveledDistance.toStringAsFixed(2)} km',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: mintColor,
                  ),
                ),
              ],
            ),
          ),
        const Spacer(),
        _buildMintIconBtn(Icons.headset_mic_rounded,
            () => context.push(AppRoutes.support), mintColor, isDark),
        const SizedBox(width: 12),
        IconButton(
          icon: Icon(
            _debugMode ? Icons.bug_report : Icons.bug_report_outlined,
            color: _debugMode ? Colors.red : Colors.grey,
          ),
          onPressed: () => setState(() => _debugMode = !_debugMode),
        ),
        const SizedBox(width: 8),
        NotificationBell(color: mintColor),
      ],
    );
  }

  Widget _buildDashboardSkeleton() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1C1F1C) : Colors.white;
    final soft = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFF1B5E20).withValues(alpha: 0.08);
    Widget block({double? width, required double height, double radius = 12}) {
      return AnimatedSkeleton(
        width: width,
        height: height,
        borderRadius: radius,
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: card,
                      shape: BoxShape.circle,
                      border: Border.all(color: soft),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: block(height: 18, radius: 8),
                  ),
                  const SizedBox(width: 12),
                  block(width: 40, height: 40, radius: 20),
                  const SizedBox(width: 10),
                  block(width: 40, height: 40, radius: 20),
                ],
              ),
              const SizedBox(height: 18),
              block(width: 120, height: 12, radius: 8),
              const SizedBox(height: 12),
              block(width: double.infinity, height: 52, radius: 16),
              const SizedBox(height: 16),
              block(width: 180, height: 34, radius: 10),
              const SizedBox(height: 10),
              block(width: 220, height: 14, radius: 8),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF121512)
                      : const Color(0xFFF7FAF7),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: soft),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: block(height: 120, radius: 16)),
                        const SizedBox(width: 12),
                        Expanded(child: block(height: 120, radius: 16)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              block(width: double.infinity, height: 200, radius: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMintIconBtn(
      IconData icon, VoidCallback onTap, Color mintColor, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: mintColor.withValues(alpha: 0.15)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: mintColor, size: 18),
      ),
    );
  }

  Widget _buildTitleSection(AppLocalizations l10n, String displayUserName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mintColor =
        isDark ? const Color(0xFF3fff8b) : const Color(0xFF1B5E20);
    final deepContainer =
        isDark ? const Color(0xFF003324) : const Color(0xFFE8F5E9);
    final subtextColor =
        isDark ? const Color(0xFF91938d) : const Color(0xFF4A6741);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.nav_home,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: deepContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: mintColor, size: 12),
                  const SizedBox(width: 6),
                  Text(
                    DynamicTranslator.of(context)
                        .translateSync(userZone ?? 'BENGALURU, KA')
                        .toUpperCase(),
                    style: TextStyle(
                      color: mintColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Manrope',
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${_getGreetingText(context)}, $displayUserName', // passed in
          style: TextStyle(
            color: subtextColor,
            fontSize: 14,
            fontFamily: 'Manrope',
          ),
        ),
      ],
    );
  }

  Widget _buildActivePolicyCard(String planName, String premium,
      AppLocalizations l10n, List<dynamic>? riders, String planTier) {
    // Get coverage items based on plan tier
    List<Map<String, dynamic>> getCoverageItems() {
      final items = <Map<String, dynamic>>[];
      final tier = planTier.toLowerCase();

      // All tiers include Rain & Heat
      items.add({
        'label': l10n.claims_heavy_rain.toUpperCase(),
        'icon': Icons.water_drop_rounded,
      });
      items.add({
        'label': l10n.claims_extreme_heat.toUpperCase(),
        'icon': Icons.wb_sunny_rounded,
      });

      // Standard & Full include Platform Downtime
      if (tier == 'standard' || tier == 'full') {
        items.add({
          'label': l10n.claims_platform_downtime.toUpperCase(),
          'icon': Icons.security_rounded,
        });
      }

      return items;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final mintColor =
        isDark ? const Color(0xFF10B981) : const Color(0xFF1B5E20);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final subtleText =
        isDark ? const Color(0xFFe1e3de) : const Color(0xFF4A6741);
    final shadowColor = isDark
        ? const Color(0xFF1B5E20).withValues(alpha: 0.04)
        : const Color(0xFF1B5E20).withValues(alpha: 0.08);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 40,
            spreadRadius: 10,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isMLFetching
                    ? 'CALCULATING AI PREMIUM...'
                    : (liveDynamicPrice != null
                        ? 'ML ADJUSTED PREMIUM'
                        : 'YOUR WEEKLY PREMIUM'),
                style: TextStyle(
                  color: _isMLFetching
                      ? Colors.orangeAccent
                      : (liveDynamicPrice != null
                          ? Colors.amberAccent
                          : subtleText),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Manrope',
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (_isMLFetching)
                    const Padding(
                      padding: EdgeInsets.only(right: 8.0, bottom: 4.0),
                      child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.orangeAccent)),
                    )
                  else
                    Text(
                      '₹$premium',
                      style: TextStyle(
                        color: liveDynamicPrice != null
                            ? Colors.amberAccent
                            : mintColor,
                        fontSize: liveDynamicPrice != null ? 30 : 26,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Manrope',
                      ),
                    ),
                  if (!_isMLFetching)
                    Text(
                      liveDynamicPrice != null ? ' (ML Adjusted)' : '/ week',
                      style: TextStyle(
                        color: liveDynamicPrice != null
                            ? Colors.amberAccent
                            : subtleText,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Manrope',
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            planName,
            style: TextStyle(
              color: textColor,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.1,
              fontFamily: 'Manrope',
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ...getCoverageItems().map((item) => _buildCoverageChip(
                    item['label'] as String,
                    item['icon'] as IconData,
                    mintColor,
                    isDark,
                  )),
              if (riders != null)
                ...riders.map((r) {
                  final name = r['name']?.toString() ?? '';
                  IconData icon = Icons.security_rounded;
                  if (name.contains('Cyclone')) icon = Icons.cyclone_rounded;
                  if (name.contains('Curfew')) icon = Icons.groups_rounded;
                  if (name.contains('Election')) {
                    icon = Icons.how_to_vote_rounded;
                  }
                  if (name.contains('App Downtime')) {
                    icon = Icons.phonelink_off_rounded;
                  }

                  return _buildCoverageChip(
                      name.replaceAll(' Rider', '').toUpperCase(),
                      icon,
                      mintColor,
                      isDark);
                }),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: mintColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: mintColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outlined, color: mintColor, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Policy locked for 91 days • Renewal only after completion',
                    style: TextStyle(
                      color: mintColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Manrope',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoPolicyCard(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final mintColor =
        isDark ? const Color(0xFF10B981) : const Color(0xFF1B5E20);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final subColor = textColor.withValues(alpha: 0.68);

    return GestureDetector(
      onTap: () => context.push(AppRoutes.policy),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: mintColor.withValues(alpha: 0.08),
              blurRadius: 30,
              spreadRadius: 6,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: mintColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: mintColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child:
                      Icon(Icons.shield_outlined, color: mintColor, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  'NO ACTIVE COVER',
                  style: TextStyle(
                    color: mintColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                    fontFamily: 'Manrope',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Protect today\'s shift income',
              style: TextStyle(
                color: textColor,
                fontSize: 31,
                height: 1.1,
                fontWeight: FontWeight.w900,
                fontFamily: 'Manrope',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No plan is active right now. Pick a shield to get automatic payouts for heavy rain, heat, and platform downtime.',
              style: TextStyle(
                color: subColor,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
                fontFamily: 'Manrope',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildCoverageChip('STARTS FROM ₹35/WEEK',
                    Icons.currency_rupee_rounded, mintColor, isDark),
                _buildCoverageChip('TAP TO VIEW PLANS', Icons.touch_app_rounded,
                    mintColor, isDark),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: mintColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shopping_bag_outlined,
                      size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'View Plans & Buy',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Manrope',
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 18, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverageChip(
      String label, IconData icon, Color mintColor, bool isDark) {
    final chipBg = isDark ? const Color(0xFF003D2A) : const Color(0xFFE8F5E9);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: mintColor, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: mintColor,
              fontSize: 9,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w900,
              fontFamily: 'Manrope',
            ),
          ),
        ],
      ),
    );
  }

  /// Earning-stability + shift hints from ML `/work-advisor` (bundled in disruptions API).
  Widget _buildWorkAdvisorCard() {
    final a = workAdvisorData;
    if (a == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF141614) : const Color(0xFFF8FAF8);
    final mintColor =
        isDark ? const Color(0xFF3fff8b) : const Color(0xFF1B5E20);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final subColor = textColor.withValues(alpha: 0.65);

    final t = DynamicTranslator.of(context);
    final esi = (a['earning_stability_index'] as num?)?.round() ?? 0;
    final band = t.translateSync(
        a['stability_band_label'] as String? ?? 'Earning outlook');
    final headline = t.translateSync(a['headline'] as String? ?? '');
    final nudge = t.translateSync(a['coverage_nudge'] as String? ?? '');
    final suggest = a['suggest_activate_coverage'] == true;
    final windows = a['recommended_shift_windows'] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mintColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: mintColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'WORK STABILITY',
                  style: TextStyle(
                    color: mintColor,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Manrope',
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: mintColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'STABILITY',
                  style: TextStyle(
                    color: mintColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Manrope',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            band,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFamily: 'Manrope',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            style: TextStyle(
              color: subColor,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
              fontFamily: 'Manrope',
            ),
          ),
          if (windows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Suggested shift focus',
              style: TextStyle(
                color: textColor.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                fontFamily: 'Manrope',
              ),
            ),
            const SizedBox(height: 6),
            ...windows.take(2).map((w) {
              final m = w is Map<String, dynamic> ? w : null;
              if (m == null) return const SizedBox.shrink();
              final label = t.translateSync(m['label'] as String? ?? '');
              final hours = m['hours'] as String? ?? '';
              final text = hours.isNotEmpty ? '$label · $hours' : label;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 16, color: mintColor.withValues(alpha: 0.85)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: subColor,
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Manrope',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (nudge.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              nudge,
              style: TextStyle(
                color: suggest ? mintColor.withValues(alpha: 0.95) : subColor,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
                fontFamily: 'Manrope',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRainAlertCard(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final mintColor =
        isDark ? const Color(0xFF3fff8b) : const Color(0xFF1B5E20);
    final textColor = Theme.of(context).colorScheme.onSurface;

    // ── Hide alert if user has active policy ──
    if (policyData != null) {
      return const SizedBox.shrink();
    }

    // ── Hide alert if no active disruptions ──
    final hasActiveDisruption = disruptionData?['active'] == true;
    if (!hasActiveDisruption) {
      // Show nice weather message instead
      return _buildNiceWeatherCard(l10n, isDark, mintColor, textColor);
    }

    // ── Get disruption trigger type for dynamic content ──
    final triggerType =
        (activeDisruption?['trigger_type'] as String? ?? 'rain').toLowerCase();

    // ── Format locality ──
    String locality = userZone ?? 'your area';
    locality = locality.replaceAll(
        RegExp(r' dark store zone', caseSensitive: false), '');
    locality = locality.replaceAll(RegExp(r' zone', caseSensitive: false), '');
    locality = locality.trim();
    if (locality.isEmpty) locality = 'your area';

    // ── Get icon and colors based on disruption type ──
    IconData alertIcon = Icons.thunderstorm_rounded;
    Color iconBg = isDark ? const Color(0xFF003D2A) : const Color(0xFFE8F5E9);
    Color alertColor = mintColor;
    String alertTitle = l10n.dashboard_rain_alert.toUpperCase();

    if (triggerType.contains('heat') || triggerType.contains('temperature')) {
      alertIcon = Icons.wb_sunny_rounded;
      iconBg = isDark ? const Color(0xFF4A2D00) : const Color(0xFFFFF3E0);
      alertColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
      alertTitle = 'EXTREME HEAT ALERT';
    } else if (triggerType.contains('downtime') ||
        triggerType.contains('platform')) {
      alertIcon = Icons.cloud_off_rounded;
      iconBg = isDark ? const Color(0xFF003D2A) : const Color(0xFFE0F2F1);
      alertColor = isDark ? const Color(0xFF4DB8AC) : const Color(0xFF00695C);
      alertTitle = 'PLATFORM DOWNTIME ALERT';
    } else if (triggerType.contains('aqi') ||
        triggerType.contains('pollution')) {
      alertIcon = Icons.air_rounded;
      iconBg = isDark ? const Color(0xFF4A2D00) : const Color(0xFFFFF3E0);
      alertColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
      alertTitle = 'AIR QUALITY WARNING';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(alertIcon, color: alertColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alertTitle,
                  style: TextStyle(
                    color: alertColor,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Manrope',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${l10n.dashboard_high_risk_prefix} $locality.\n${l10n.dashboard_secure_coverage}',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Manrope',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => context.push(AppRoutes.policy),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: alertColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Text(
                    l10n.dashboard_activate,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF0a0b0a) : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Manrope',
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded,
                      color: isDark ? const Color(0xFF0a0b0a) : Colors.white,
                      size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNiceWeatherCard(
      AppLocalizations l10n, bool isDark, Color mintColor, Color textColor) {
    final cardColor = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final lightGreen =
        isDark ? const Color(0xFF003D2A) : const Color(0xFFE8F5E9);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: lightGreen,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.wb_sunny_rounded, color: mintColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WEATHER CLEAR',
                  style: TextStyle(
                    color: mintColor,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Manrope',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Good conditions for work today!\nStay protected with a plan.',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Manrope',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictiveNudgeCard(AppLocalizations l10n) {
    if (nudgeData == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF0D1410) : const Color(0xFFE8F5E9);
    final mintColor =
        isDark ? const Color(0xFF3fff8b) : const Color(0xFF1B5E20);
    final textColor = Theme.of(context).colorScheme.onSurface;

    final t = DynamicTranslator.of(context);
    final date =
        t.translateSync(nudgeData!['nudge_date'] as String? ?? 'Friday');
    final prob = nudgeData!['probability_percentage']?.toString() ?? '85';
    final desc = t.translateSync(
        nudgeData!['description'] as String? ?? 'Heavy rain expected.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mintColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: mintColor.withValues(alpha: 0.1),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: mintColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'PROPHET AI NUDGE',
                style: TextStyle(
                  color: mintColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  fontFamily: 'Manrope',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '🌧️ $prob% Risk of Heavy Rain on $date',
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontFamily: 'Manrope',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            policyData != null
                ? '$desc\nYour active ${policyData!['plan_name']} will auto-cover any washout shifts.'
                : '$desc\nCoverage starts next Monday — activate quarterly plan now to secure your income.',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.8),
              fontSize: 13,
              height: 1.4,
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCards(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                Icons.shield_outlined,
                l10n.dashboard_modular,
                l10n.dashboard_add_coverage,
                () => context.push(AppRoutes.policy),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionCard(
                Icons.article_outlined,
                l10n.dashboard_legal,
                l10n.dashboard_view_cert,
                () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.dashboard_generating_cert),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  );

                  Map<String, dynamic>? certPolicy = policyData;
                  final uid =
                      userId ?? await StorageService.instance.getUserId();

                  // Always try to fetch the freshest active policy before generating.
                  if (uid != null) {
                    try {
                      final fresh = await ApiService.instance.getPolicy(uid);
                      final freshPolicy =
                          fresh['policy'] as Map<String, dynamic>?;
                      final status =
                          freshPolicy?['status']?.toString().toLowerCase() ??
                              '';
                      if (freshPolicy != null &&
                          (status == 'active' || status == 'renewed')) {
                        certPolicy = freshPolicy;
                        if (mounted) {
                          setState(() => policyData = {
                                ...freshPolicy,
                                if (!freshPolicy.containsKey('start_date'))
                                  'start_date': freshPolicy['coverage_start'],
                                if (!freshPolicy.containsKey('end_date'))
                                  'end_date': freshPolicy['commitment_end'] ??
                                      freshPolicy['paid_until'],
                                'plan_name': _planDisplayName(
                                    freshPolicy['plan_tier'] as String?),
                              });
                        }
                      }
                    } catch (_) {
                      // Use in-memory policy data if refresh fails.
                    }
                  }

                  if (certPolicy == null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'No active policy found to generate certificate.')),
                    );
                    return;
                  }

                  final latestName = (userName?.trim().isNotEmpty ?? false)
                      ? userName!.trim()
                      : (await StorageService.instance.getUserName())?.trim();
                  final latestZone = (userZone?.trim().isNotEmpty ?? false)
                      ? userZone!.trim()
                      : (await StorageService.instance.getUserZone())?.trim();

                  final rawStart = certPolicy['coverage_start'] as String? ??
                      certPolicy['start_date'] as String?;
                  final rawEnd = certPolicy['commitment_end'] as String? ??
                      certPolicy['paid_until'] as String? ??
                      certPolicy['end_date'] as String?;

                  await PdfGenerator.generateAndPreviewCertificate(
                    name: latestName != null && latestName.isNotEmpty
                        ? latestName
                        : 'Unknown Worker',
                    zone: latestZone != null && latestZone.isNotEmpty
                        ? latestZone
                        : 'Unknown Zone',
                    planName: _planNameWithRiders(certPolicy),
                    policyNumber: _formatPolicyNumber(certPolicy),
                    coverageStart:
                        rawStart != null ? DateTime.tryParse(rawStart) : null,
                    coverageEnd:
                        rawEnd != null ? DateTime.tryParse(rawEnd) : null,
                    weeklyPremium: _resolveWeeklyPremium(certPolicy),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(
      IconData icon, String kicker, String label, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final mintColor =
        isDark ? const Color(0xFF3fff8b) : const Color(0xFF1B5E20);
    final iconBg = isDark ? const Color(0xFF003D2A) : const Color(0xFFE8F5E9);
    final subtextColor =
        isDark ? const Color(0xFF91938d) : const Color(0xFF4A6741);
    final textColor = Theme.of(context).colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: mintColor, size: 22)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicker,
                  style: TextStyle(
                    color: subtextColor,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Manrope',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Manrope',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationStatusBanner(BuildContext context,
      {required bool isGpsOff}) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.errorContainer;
    final fg = theme.colorScheme.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_off_rounded, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isGpsOff
                      ? 'Turn on GPS before going online'
                      : 'Location access is incomplete',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isGpsOff
                ? 'You can still browse the app, but shift protection and live zone tracking need device location turned on.'
                : 'You can keep using Hustlr normally. We will ask again only when you need protected tracking.',
            style: theme.textTheme.bodyMedium?.copyWith(color: fg),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              if (isGpsOff) {
                await Geolocator.openLocationSettings();
              } else {
                await openAppSettings();
              }
              _checkLocationPermission();
            },
            child: Text(isGpsOff ? 'Turn On GPS' : 'Open Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildMissedPayoutsCard(
      int amount, BuildContext context, AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final mintColor =
        isDark ? const Color(0xFF3fff8b) : const Color(0xFF1B5E20);
    final pinkColor =
        isDark ? const Color(0xFFff8ba0) : const Color(0xFFE91E63);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final subtextColor =
        isDark ? const Color(0xFF91938d) : const Color(0xFF4A6741);

    return GestureDetector(
      onTap: () => context.push(AppRoutes.shadowPolicy),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.savings_rounded, color: pinkColor, size: 32),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: mintColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        l10n.dashboard_see_why,
                        style: TextStyle(
                          color: mintColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'Manrope',
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          color: mintColor, size: 14),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '₹$amount',
              style: TextStyle(
                color: textColor,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1.2,
                fontFamily: 'Manrope',
              ),
            ),
            Text(
              l10n.dashboard_missed_payouts,
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Manrope',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.dashboard_potential_loss,
              style: TextStyle(
                color: subtextColor,
                fontSize: 13,
                fontFamily: 'Manrope',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🔧 DEBUG MODE — TESTING ONLY',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Divider(color: Colors.red.withValues(alpha: 0.3)),

          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  minimumSize: const Size(60, 28),
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 10),
                ),
                onPressed: () => _loadDashboardData(),
                child: const Text('REFRESH',
                    style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(60, 28),
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 10),
                ),
                onPressed: () {
                  // Simulate a rain event locally for UI
                  if (mounted) {
                    setState(() {
                      disruptionData = {
                        'active': true,
                        'trigger_type': 'Heavy Rain',
                        'zone': userZone ?? 'Your Zone',
                      };
                      activeDisruption = disruptionData;
                    });
                  }
                },
                child:
                    const Text('RAIN', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  minimumSize: const Size(60, 28),
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 10),
                ),
                onPressed: () => _checkLocationPermission(),
                child: const Text('GPS', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: FraudSensorService.mockFraudSpoofing
                      ? Colors.green
                      : Colors.grey[800],
                  minimumSize: const Size(60, 28),
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 10),
                ),
                onPressed: () async {
                  var newVal = !FraudSensorService.mockFraudSpoofing;
                  if (mounted) {
                    setState(() {
                      FraudSensorService.mockFraudSpoofing = newVal;
                    });
                    if (newVal) {
                      await StorageService.instance.setLastLat(13.0012);
                      await StorageService.instance.setLastLng(80.2565);
                      setState(() {
                        disruptionData = {
                          'active': true,
                          'trigger_type': 'Heavy Rain',
                          'zone': userZone ?? 'Your Zone',
                          'weather_source': 'mock_spoof',
                          'rain_mm': 72.4,
                          'severity': 0.85,
                        };
                        activeDisruption = disruptionData;
                      });
                      AppEvents.instance.claimUpdated();
                      AppEvents.instance.walletUpdated();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content:
                              Text('🌧 SPOOF ON — Rain disruption injected'),
                          backgroundColor: Color(0xFF10B981)));
                    } else {
                      setState(() {
                        activeDisruption = null;
                        disruptionData = null;
                      });
                    }
                    LocationService.instance.updateFromGps(
                        LocationService.instance.currentLat,
                        LocationService.instance.currentLon);
                  }
                },
                child: Text(
                    FraudSensorService.mockFraudSpoofing
                        ? 'SPOOF (ON)'
                        : 'SPOOF (OFF)',
                    style: const TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _enableLiveML ? Colors.amber[800] : Colors.grey[800],
                  minimumSize: const Size(60, 28),
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 10),
                ),
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _enableLiveML = !_enableLiveML;
                    });
                    if (_enableLiveML) {
                      _fetchLiveMLData(policyData?['plan_tier'] ?? 'standard');
                    } else {
                      setState(() {
                        liveDynamicPrice = null;
                        liveIssScore = null;
                      });
                    }
                  }
                },
                child: Text(_enableLiveML ? 'ML SYNC (ON)' : 'ML SYNC (OFF)',
                    style: const TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  minimumSize: const Size(60, 28),
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 10),
                ),
                onPressed: () async {
                  await AuthService.logout();
                  if (!mounted) return;
                  context.read<MockDataService>().resetDemo();
                  context.go(AppRoutes.login);
                },
                child:
                    const Text('LOGOUT', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _DebugHeader('--- USER STATE ---'),
          _DebugRow('USER ID', userId ?? 'NULL'),
          _DebugRow('NAME', userName ?? 'NULL'),
          _DebugRow('ZONE', userZone ?? 'NULL'),

          _DebugHeader('--- POLICY STATE ---'),
          _DebugRow('POLICY ID', policyData?['id']?.toString() ?? 'NULL'),
          _DebugRow(
              'PLAN TIER', policyData?['plan_tier']?.toString() ?? 'NULL'),
          _DebugRow('WEEKLY PREMIUM',
              policyData?['weekly_premium']?.toString() ?? 'NULL'),
          _DebugRow('STATUS', policyData?['status']?.toString() ?? 'NULL'),

          _DebugHeader('--- WALLET STATE ---'),
          Builder(builder: (context) {
            final rawBal = (walletData?['balance'] as num?)?.toInt();
            String balStr = 'NULL';
            if (rawBal != null) {
              balStr =
                  rawBal < 0 ? '0 (paid: ${rawBal.abs()})' : rawBal.toString();
            }
            return _DebugRow('BALANCE', balStr);
          }),
          _DebugRow('TOTAL PAYOUTS',
              walletData?['total_payouts']?.toString() ?? 'NULL'),
          _DebugRow('TOTAL PREMIUMS',
              walletData?['total_premiums']?.toString() ?? 'NULL'),
          _DebugRow('TRANSACTION COUNT',
              (walletData?['transactions'] as List?)?.length.toString() ?? '0'),

          _DebugHeader('--- DISRUPTION STATE ---'),
          _DebugRow(
              'WEATHER SOURCE',
              // API sends 'source'; some older responses have 'station'
              weatherData?['source']?.toString() ??
                  weatherData?['station']?.toString() ??
                  'NULL'),
          _DebugRow('RAIN MM', '${weatherData?['rainfall_mm_1h'] ?? 'NULL'}'),
          _DebugRow('TEMP', '${weatherData?['temp_celsius'] ?? 'NULL'}°C'),
          _DebugRow('TRIGGER ACTIVE',
              disruptionData?['active']?.toString() ?? 'false'),
          _DebugRow('TRIGGER TYPE',
              disruptionData?['trigger_type']?.toString() ?? 'NONE'),

          _DebugHeader('--- API STATE ---'),
          _DebugRow('BACKEND URL', ApiService.baseUrl),
          const SizedBox(height: 8),
          // ── Live API Health Check ──────────────────────────────────
          if (_apiHealthStatus.isEmpty)
            GestureDetector(
              onTap: _checkApiHealth,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('▶ RUN API HEALTH CHECK',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            )
          else if (_apiHealthStatus['_loading'] == 'true')
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF3FFF8B))),
                SizedBox(width: 10),
                Text('Pinging endpoints...',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
              ]),
            )
          else ...[
            ..._apiHealthStatus.entries.map((e) => _DebugRow(e.key, e.value)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _checkApiHealth,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('↻ RE-RUN CHECK',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],

          _DebugHeader('--- LOCATION STATE ---'),
          _DebugRow('LOCATION PERMISSION', _locationPermissionStatus),
          _DebugRow('LAST GPS LAT',
              _lastLat == 0.0 ? 'NO FIX YET' : _lastLat.toStringAsFixed(6)),
          _DebugRow('LAST GPS LNG',
              _lastLng == 0.0 ? 'NO FIX YET' : _lastLng.toStringAsFixed(6)),
          _DebugRow('ZONE DEPTH SCORE', _zoneDepthScore.toStringAsFixed(1)),
          _DebugRow(
              'BACKGROUND TRACKING', _backgroundTrackingActive.toString()),
        ],
      ),
    );
  }

  Widget _buildSystemStatusFeed() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1c1f1c) : const Color(0xFFF0F4F0);
    final textColor =
        isDark ? const Color(0xFF91938d) : const Color(0xFF4A6741);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final time =
              "${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}";
          return Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Row(
              children: [
                Text(
                  "[$time] ",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  event.message,
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLiveStatsRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statsColor =
        isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32);
    final distance = LocationService.instance.traveledDistance;

    return Row(
      children: [
        _buildStatItem(
          icon: Icons.speed_rounded,
          label: 'Protected',
          value: '${distance.toStringAsFixed(2)} km',
          color: statsColor,
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1c1f1c) : const Color(0xFFE8F5E9);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: color.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugHeader extends StatelessWidget {
  final String title;
  const _DebugHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.yellow,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DebugRow extends StatelessWidget {
  final String keyName;
  final String valName;
  const _DebugRow(this.keyName, this.valName);

  @override
  Widget build(BuildContext context) {
    return Text(
      '$keyName: $valName',
      style: const TextStyle(
        color: Colors.greenAccent,
        fontSize: 11,
        fontFamily: 'monospace',
      ),
    );
  }
}

class _SystemFeedEvent {
  final String message;
  final DateTime timestamp;

  const _SystemFeedEvent(this.message, this.timestamp);
}
