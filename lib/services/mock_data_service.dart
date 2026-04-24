import 'package:flutter/foundation.dart';
import '../core/services/storage_service.dart';
import '../core/services/api_service.dart';
import '../models/claim.dart' as domain;
import 'package:hive_flutter/hive_flutter.dart';
import 'location_service.dart';
import 'fraud_sensor_service.dart';
import 'app_events.dart';

class WorkerModel {
  final String id;
  final String name;
  final String platform;
  final String city;
  final String zone;
  final int weeklyIncomeEstimate;
  /// Income stability score (UI / analytics); optional for backward compatibility.
  final int issScore;

  WorkerModel({
    required this.id,
    required this.name,
    required this.platform,
    required this.city,
    required this.zone,
    required this.weeklyIncomeEstimate,
    this.issScore = 62,
  });

  WorkerModel copyWith({
    String? zone,
    int? issScore,
  }) {
    return WorkerModel(
      id: id,
      name: name,
      platform: platform,
      city: city,
      zone: zone ?? this.zone,
      weeklyIncomeEstimate: weeklyIncomeEstimate,
      issScore: issScore ?? this.issScore,
    );
  }
}

class PolicyModel {
  final String plan;
  final int premium;
  final String status;
  final String coverageStart;
  final String coverageEnd;
  final List<String> riders;
  final String coverageDescription;

  PolicyModel({
    required this.plan,
    required this.premium,
    required this.status,
    required this.coverageStart,
    required this.coverageEnd,
    required this.riders,
    required this.coverageDescription,
  });

  PolicyModel copyWith({
    String? plan,
    int? premium,
    String? status,
    String? coverageStart,
    String? coverageEnd,
    List<String>? riders,
    String? coverageDescription,
  }) {
    return PolicyModel(
      plan: plan ?? this.plan,
      premium: premium ?? this.premium,
      status: status ?? this.status,
      coverageStart: coverageStart ?? this.coverageStart,
      coverageEnd: coverageEnd ?? this.coverageEnd,
      riders: riders ?? this.riders,
      coverageDescription: coverageDescription ?? this.coverageDescription,
    );
  }
}

class TimelineStep {
  final String title;
  final String date;
  final bool isDone;
  final bool isPending;

  TimelineStep({
    required this.title,
    required this.date,
    this.isDone = false,
    this.isPending = false,
  });
}

class ClaimModel {
  final String id;
  final String type;
  final String date;
  final int amount;
  String status;
  final String zone;
  final String icon;
  final List<TimelineStep> timeline;
  final int? frsScore;
  final int? durationHours;
  final int? ratePerHour;
  final int? grossAmount;
  final int? immediateAmount;
  final int? heldAmount;
  final String? releaseDate;

  ClaimModel({
    required this.id,
    required this.type,
    required this.date,
    required this.amount,
    required this.status,
    required this.zone,
    required this.icon,
    this.timeline = const [],
    this.frsScore,
    this.durationHours,
    this.ratePerHour,
    this.grossAmount,
    this.immediateAmount,
    this.heldAmount,
    this.releaseDate,
  });
}

class NudgeModel {
  final String type;
  final String message;
  final String ctaText;
  final String targetRoute;

  NudgeModel({
    required this.type,
    required this.message,
    required this.ctaText,
    required this.targetRoute,
  });
}

class ShadowEventModel {
  final String triggerIcon;
  final String triggerName;
  final String date;
  final int claimableAmount;

  ShadowEventModel({
    required this.triggerIcon,
    required this.triggerName,
    required this.date,
    required this.claimableAmount,
  });
}

class ZoneRiskFactor {
  final String icon;
  final String label;
  final int percentage;

  ZoneRiskFactor({
    required this.icon,
    required this.label,
    required this.percentage,
  });
}

class ZoneRiskModel {
  final String city;
  final String zone;
  final String riskTier;
  final List<ZoneRiskFactor> factors;

  ZoneRiskModel({
    required this.city,
    required this.zone,
    required this.riskTier,
    required this.factors,
  });
}

class LiveStatusModel {
  final String icon;
  final String name;
  final double level;
  final String statusText;

  LiveStatusModel({
    required this.icon,
    required this.name,
    required this.level,
    required this.statusText,
  });
}

class ActiveDisruption {
  final String triggerName;
  final String triggerIcon;
  final String message;
  final int payoutExpected;
  final String creditDate;
  bool isActive;

  ActiveDisruption({
    required this.triggerName,
    required this.triggerIcon,
    required this.message,
    required this.payoutExpected,
    required this.creditDate,
    required this.isActive,
  });
}

class PremiumBreakdownFactor {
  final String factor;
  final int adjustment;
  final String reason;
  PremiumBreakdownFactor({required this.factor, required this.adjustment, required this.reason});
}

class PremiumComparison {
  final String zone;
  final int rate;
  PremiumComparison({required this.zone, required this.rate});
}

class PremiumBreakdownModel {
  final int baseRate;
  final List<PremiumBreakdownFactor> factors;
  final int finalRate;
  final List<PremiumComparison> comparison;
  PremiumBreakdownModel({
    required this.baseRate,
    required this.factors,
    required this.finalRate,
    required this.comparison,
  });
}

class WeeklyDisruption {
  final int week;
  final int rain;
  final int heat;
  final int platform;
  WeeklyDisruption({required this.week, required this.rain, required this.heat, required this.platform});
}

class AnalyticsModel {
  final int earningsProtected;
  final int disruptionEventsCount;
  final List<WeeklyDisruption> weeklyHours;
  AnalyticsModel({
    required this.earningsProtected,
    required this.disruptionEventsCount,
    required this.weeklyHours,
  });
}

// ─── Helper to map API trigger_type → display label + icon ───────────────────
String _triggerLabel(String t) {
  const m = {
    'rain_heavy': 'Rain Disruption',
    'rain_moderate': 'Rain Disruption',
    'rain_light': 'Rain Disruption',
    'heat_severe': 'Extreme Heat',
    'heat_stress': 'Extreme Heat',
    'aqi_hazardous': 'Air Quality Alert',
    'aqi_very_unhealthy': 'Air Quality Alert',
    'platform_outage': 'Platform Downtime',
    'dark_store_closure': 'Dark Store Closure',
  };
  return m[t] ?? t;
}

String _triggerIcon(String t) {
  if (t.startsWith('rain')) return 'rain';
  if (t.startsWith('heat')) return 'heat';
  if (t.startsWith('aqi')) return 'heat';
  if (t.startsWith('platform')) return 'downtime';
  return 'downtime';
}

String _planLabel(String tier) {
  const m = {
    'basic': 'Basic Shield',
    'standard': 'Standard Shield',
    'full': 'Full Shield',
  };
  return m[tier] ?? tier;
}

class MockDataService extends ChangeNotifier {
  static final MockDataService instance = MockDataService._internal();
  
  /// Demo bridge: set by main.dart so disruption triggers also flow through
  /// ClaimsBloc. Receives an immutable [domain.Claim] when a claim is approved.
  void Function(domain.Claim claim)? onClaimApproved;

  MockDataService._internal() {
    syncWithStorage();
  }

  // Backwards compatibility for Provider
  factory MockDataService() => instance;

  Box? _appDataBoxOrNull() {
    try {
      if (Hive.isBoxOpen('appData')) return Hive.box('appData');
    } catch (_) {}
    return null;
  }

  bool _isUuid(String value) {
    final v = value.trim();
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(v);
  }

  // ── State ──────────────────────────────────────────────────────────────────

  WorkerModel worker = WorkerModel(
    id: '',
    name: '',
    platform: '',
    city: '',
    zone: '',
    weeklyIncomeEstimate: 0,
  );

  bool hasActivePolicy = false;
  PolicyModel activePolicy = PolicyModel(
    plan: "Standard Shield",
    premium: 49,
    status: "ACTIVE",
    coverageStart: "26 Oct 2025",
    coverageEnd: "25 Oct 2026",
    riders: ["Bandh / Curfew", "Internet Blackout"],
    coverageDescription: "Rain, heat, pollution, AQI > 200, bandh, internet blackout",
  );

  int walletBalance = 0;
  int monthlySavings = 0;
  int totalPremiums = 0;
  int potentialLoss = 2100;
  bool showPredictiveNudge = true;

  // ML & Debug Overrides
  bool simulateHighIss = true;
  bool forceFraudFlag = false;
  String? spoofedZone;

  List<ClaimModel> claims = [];

  ActiveDisruption? activeDisruption;

  PremiumBreakdownModel premiumBreakdown = PremiumBreakdownModel(
    baseRate: 55,
    finalRate: 49,
    factors: [
      PremiumBreakdownFactor(factor: "Base rate (Standard Shield)", adjustment: 55, reason: "—"),
      PremiumBreakdownFactor(factor: "Zone flood risk (Adyar, 0.62)", adjustment: 0, reason: "Moderate — no surcharge ✅"),
      PremiumBreakdownFactor(factor: "Regional behavior index (0.65)", adjustment: 0, reason: "Within normal range ✅"),
      PremiumBreakdownFactor(factor: "Platform outage rate", adjustment: -3, reason: "Zepto uptime > 97% ✅"),
      PremiumBreakdownFactor(factor: "Clean claim history (4 weeks)", adjustment: -3, reason: "No claims this season ✅"),
    ],
    comparison: [
      PremiumComparison(zone: "Velachery", rate: 55),
      PremiumComparison(zone: "Adyar (your zone)", rate: 49),
      PremiumComparison(zone: "Anna Nagar", rate: 34),
    ],
  );

  AnalyticsModel analytics = AnalyticsModel(
    earningsProtected: 2190,
    disruptionEventsCount: 3,
    weeklyHours: [
      WeeklyDisruption(week: 1, rain: 2, heat: 0, platform: 0),
      WeeklyDisruption(week: 2, rain: 0, heat: 3, platform: 2),
      WeeklyDisruption(week: 3, rain: 0, heat: 0, platform: 0),
      WeeklyDisruption(week: 4, rain: 3, heat: 0, platform: 0),
    ],
  );

  Map<String, List<String>> autocompleteCities = {
    'Chennai': ['Velachery', 'Anna Nagar', 'OMR (Old Mahabalipuram Road)', 'Adyar', 'Tambaram', 'Porur', 'Perambur', 'Korattur', 'T Nagar', 'Mylapore', 'Kattankulathur'],
    'Bengaluru': ['Koramangala', 'HSR Layout', 'Whitefield', 'Electronic City', 'Indiranagar', 'Marathahalli', 'Jayanagar', 'BTM Layout', 'Hebbal', 'Sarjapur Road'],
    'Mumbai': ['Andheri', 'Bandra', 'Powai', 'Thane', 'Borivali', 'Kurla', 'Dadar', 'Malad', 'Goregaon', 'Vile Parle'],
    'Delhi': ['Lajpat Nagar', 'Dwarka', 'Rohini', 'Saket', 'Noida Sector 18', 'Greater Kailash', 'Janakpuri', 'Vasant Kunj', 'Pitampura', 'Karol Bagh'],
    'Hyderabad': ['Hitech City', 'Kondapur', 'Gachibowli', 'Madhapur', 'Begumpet', 'Kukatpally', 'Miyapur', 'Banjara Hills', 'Jubilee Hills', 'Ameerpet'],
  };

  List<NudgeModel> nudges = [
    NudgeModel(type: "Heavy rain", message: "72-hr forecast: 78% rain probability Friday 2–6 PM in Adyar. Activate ₹49 Standard Shield now to protect ₹360 Friday earnings.", ctaText: "ACTIVATE NOW →", targetRoute: "/policy"),
    NudgeModel(type: "Internet outage", message: "Internet outage risk this week in your zone — add Internet Blackout cover", ctaText: "ADD COVER →", targetRoute: "/policy"),
    NudgeModel(type: "High traffic", message: "High traffic week forecast — GST Road corridor at risk Thursday evening", ctaText: "ADD COVER →", targetRoute: "/policy"),
    NudgeModel(type: "Platform downtime", message: "Platform downtime last Tuesday cost you ₹100 — you weren't covered", ctaText: "SEE PLANS →", targetRoute: "/policy"),
  ];
  int currentNudgeIndex = 0;

  NudgeModel get currentNudge => nudges[currentNudgeIndex];

  bool showShadowNudge = true;
  int missedAmount = 220;
  int missedEventsCount = 2;

  List<ShadowEventModel> shadowEvents = [
    ShadowEventModel(triggerIcon: "rain", triggerName: "Rain Disruption", date: "Oct 12, 2025", claimableAmount: 120),
    ShadowEventModel(triggerIcon: "downtime", triggerName: "Platform Downtime", date: "Oct 8, 2025", claimableAmount: 100),
  ];

  ZoneRiskModel zoneRisk = ZoneRiskModel(
    city: "Chennai",
    zone: "Adyar Dark Store Zone",
    riskTier: "HIGH FLOOD RISK",
    factors: [
      ZoneRiskFactor(icon: "rain", label: "Flood frequency", percentage: 85),
      ZoneRiskFactor(icon: "downtime", label: "Platform outage rate", percentage: 45),
      ZoneRiskFactor(icon: "heat", label: "Traffic congestion", percentage: 55),
    ],
  );

  List<LiveStatusModel> liveStatuses = [
    LiveStatusModel(icon: "rain", name: "Rain", level: 0.1, statusText: "12mm/hr · Threshold 64.5mm/hr · IMD"),
    LiveStatusModel(icon: "heat", name: "Heat Wave", level: 0.85, statusText: "41°C · Threshold 43°C · IMD"),
    LiveStatusModel(icon: "downtime", name: "Platform", level: 0.05, statusText: "Operational · 99% uptime · Zepto API"),
    LiveStatusModel(icon: "internet", name: "Internet", level: 0.15, statusText: "45 Mbps avg · Normal · TRAI"),
    LiveStatusModel(icon: "strike", name: "Bandh/Strike", level: 0.0, statusText: "No alerts · NLP scraper clear"),
  ];

  List<double> issHistory = [55, 60, 52, 68, 58, 62];

  List<Map<String, dynamic>> transactions = [];

  // ── Sync ──────────────────────────────────────────────────────────────────

  /// Populate from local storage (fast) then hydrate from API (async).
  void syncWithStorage() {
    final box = _appDataBoxOrNull();
    final name = box?.get('userName') ?? StorageService.getString('userName') ?? StorageService.getString('workerName') ?? '';
    final city = box?.get('userCity') ?? StorageService.getString('userCity') ?? StorageService.getString('workerCity') ?? '';
    final zone = box?.get('userZone') ?? StorageService.getString('userZone') ?? StorageService.getString('workerZone') ?? '';
    final platform = box?.get('userPlatform') ?? StorageService.getString('userPlatform') ?? StorageService.getString('workerPlatform') ?? '';
    final userId = StorageService.userId;

    worker = WorkerModel(
      id: userId.isNotEmpty ? userId : '',
      name: name,
      platform: platform,
      city: city,
      zone: zone,
      weeklyIncomeEstimate: 0,
    );

    // Restore persisted demo state (survives app restarts)
    final savedBalance = box?.get('demo_walletBalance');
    final savedSavings = box?.get('demo_monthlySavings');
    final savedTx = box?.get('demo_transactions');
    final savedClaims = box?.get('demo_claims');

    if (savedBalance != null) walletBalance = savedBalance as int;
    if (savedSavings != null) monthlySavings = savedSavings as int;
    if (box?.containsKey('demo_hasActivePolicy') == true) {
      hasActivePolicy = box!.get('demo_hasActivePolicy') as bool;
      final savedTier = box.get('demo_activePolicyTier') as String?;
      if (savedTier != null && hasActivePolicy) {
        _updateActivePolicyModel(savedTier);
      }
    }
    if (savedTx != null) {
      transactions = (savedTx as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (savedClaims != null) {
      final rawClaims = savedClaims as List;
      claims = rawClaims.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return ClaimModel(
          id: m['id'] as String,
          type: m['type'] as String,
          date: m['date'] as String,
          amount: m['amount'] as int,
          status: m['status'] as String,
          zone: m['zone'] as String,
          icon: m['icon'] as String,
          grossAmount: m['grossAmount'] as int?,
          immediateAmount: m['immediateAmount'] as int?,
          heldAmount: m['heldAmount'] as int?,
        );
      }).toList();
    }

    notifyListeners();

    // Always load live zone data (AQI, Weather, NewsAPI) — no login required
    _hydrateZoneData(zone);

    // If we have a real userId, also hydrate user-specific data
    if (userId.isNotEmpty && _isUuid(userId)) {
      _hydrateFromApi(userId);
    }
  }

  /// Persist demo state to Hive so it survives hot restarts.
  Future<void> _persistDemoState() async {
    final box = _appDataBoxOrNull();
    if (box == null) return;
    await box.put('demo_walletBalance', walletBalance);
    await box.put('demo_monthlySavings', monthlySavings);
    await box.put('demo_transactions', transactions);
    await box.put('demo_hasActivePolicy', hasActivePolicy);
    await box.put('demo_activePolicyTier', activePolicy.plan.toLowerCase().replaceAll(' shield', ''));
    await box.put('demo_claims', claims.map((c) => {
      'id': c.id,
      'type': c.type,
      'date': c.date,
      'amount': c.amount,
      'status': c.status,
      'zone': c.zone,
      'icon': c.icon,
      'grossAmount': c.grossAmount,
      'immediateAmount': c.immediateAmount,
      'heldAmount': c.heldAmount,
    }).toList());
  }

  /// Loads live zone-specific data (AQI, Weather, Bandh/NLP) — no userId needed.
  Future<void> _hydrateZoneData(String zone) async {
    if (zone.isEmpty) return;
    try {
      final data = await ApiService.instance.getDisruptions(zone);

      final aqiData = data['aqi'] as Map<String, dynamic>?;
      final weatherData = data['weather'] as Map<String, dynamic>?;
      final newsAlert = data['news_alert'] as Map<String, dynamic>?;
      final platform = data['platform'] as Map<String, dynamic>?;

      if (aqiData != null) {
        final aqiVal = (aqiData['current'] as num?)?.toDouble() ?? 0;
        final aqiLevel = aqiData['level'] as String? ?? 'Unknown';
        final pm25 = (aqiData['pm25'] as num?)?.toDouble() ?? 0;
        final station = aqiData['station'] as String? ?? 'AQICN';
        final aqiIdx = liveStatuses.indexWhere((s) => s.name == 'Air Quality');
        final aqiStatus = LiveStatusModel(
          icon: 'heat',
          name: 'Air Quality',
          level: (aqiVal / 500).clamp(0.0, 1.0),
          statusText: 'AQI $aqiVal · PM2.5 ${pm25.toStringAsFixed(1)} · $aqiLevel · $station',
        );
        if (aqiIdx != -1) {
          liveStatuses[aqiIdx] = aqiStatus;
        } else {
          liveStatuses.add(aqiStatus);
        }
      }

      if (weatherData != null) {
        final rain = (weatherData['rainfall_mm_1h'] as num?)?.toDouble() ?? 0;
        final temp = (weatherData['temp_celsius'] as num?)?.toDouble() ?? 0;
        final condition = weatherData['condition'] as String? ?? '';
        final rainIdx = liveStatuses.indexWhere((s) => s.name == 'Rain');
        if (rainIdx != -1) {
          liveStatuses[rainIdx] = LiveStatusModel(
            icon: 'rain', name: 'Rain',
            level: (rain / 64.5).clamp(0.0, 1.0),
            statusText: '${rain.toStringAsFixed(1)}mm/hr · Threshold 64.5mm/hr · $condition',
          );
        }
        final heatIdx = liveStatuses.indexWhere((s) => s.name == 'Heat Wave');
        if (heatIdx != -1) {
          liveStatuses[heatIdx] = LiveStatusModel(
            icon: 'heat', name: 'Heat Wave',
            level: ((temp - 30) / 15).clamp(0.0, 1.0),
            statusText: '${temp.toStringAsFixed(1)}°C · Threshold 43°C · $condition',
          );
        }
      }

      if (newsAlert != null && newsAlert['detected'] == true) {
        final confidence = (newsAlert['confidence'] as num?)?.toDouble() ?? 0;
        final headline = newsAlert['headline'] as String? ?? 'Disruption detected';
        final strikeIdx = liveStatuses.indexWhere((s) => s.name == 'Bandh/Strike');
        if (strikeIdx != -1) {
          liveStatuses[strikeIdx] = LiveStatusModel(
            icon: 'strike', name: 'Bandh/Strike',
            level: confidence,
            statusText: '${(confidence * 100).round()}% confidence · $headline',
          );
        }
      }

      if (platform != null) {
        final failRate = (platform['failure_rate'] as num?)?.toDouble() ?? 0;
        final platformIdx = liveStatuses.indexWhere((s) => s.name == 'Platform');
        if (platformIdx != -1) {
          liveStatuses[platformIdx] = LiveStatusModel(
            icon: 'downtime', name: 'Platform',
            level: failRate.clamp(0.0, 1.0),
            statusText: failRate > 0.1
                ? 'Failure rate ${(failRate * 100).round()}% · Disrupted'
                : 'Operational · ${((1 - failRate) * 100).round()}% uptime',
          );
        }
      }

      final isActive = data['active'] as bool? ?? false;
      if (isActive && activeDisruption == null) {
        final disruptions = data['disruptions'] as List<dynamic>? ?? [];
        if (disruptions.isNotEmpty) {
          final d = disruptions.first as Map<String, dynamic>;
          final tType = d['trigger_type'] as String? ?? 'disruption';
          activeDisruption = ActiveDisruption(
            triggerName: _triggerLabel(tType),
            triggerIcon: tType.contains('rain') ? 'rain' : (tType.contains('heat') ? 'heat' : 'app'),
            message: '${_triggerLabel(tType)} active in your zone',
            payoutExpected: (d['hourly_rate'] as num?)?.toInt() ?? 0,
            creditDate: 'Auto-disbursed upon confirmation',
            isActive: true,
          );
        }
      }

      notifyListeners();
      debugPrint('[MockDataService] Zone data hydrated from live API ✅');
    } catch (e) {
      debugPrint('[MockDataService] Zone hydration error: $e');
    }
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    if (v is String) return double.tryParse(v)?.toInt() ?? 0;
    return 0;
  }

  Future<void> _hydrateFromApi(String userId) async {
    try {
      final box = _appDataBoxOrNull();
      final hasDemoData = box?.containsKey('demo_walletBalance') == true;

      // Fetch wallet
      final wallet = await ApiService.instance.getWallet(userId);
      // Don't overwrite demo state — demo claims/balance take priority for presentation
      if (!hasDemoData) {
        walletBalance = _asInt(wallet['balance']);
        monthlySavings = _asInt(wallet['total_payouts']);
        totalPremiums = _asInt(wallet['total_premiums']);
        final rawTx = wallet['transactions'] as List<dynamic>? ?? [];
        transactions = rawTx.map((t) => {
          'type': t['type'],
          'title': t['description'] ?? (t['type'] == 'credit' ? 'Payout Credited' : 'Premium Deducted'),
          'subtitle': t['reference'] ?? '',
          'amount': _asInt(t['amount']),
          'date': _formatDate(t['created_at'] as String?),
        }).toList();

        // Fetch claims
        final rawClaims = await ApiService.getClaimsList(userId);
        if (rawClaims.isNotEmpty) {
          claims = rawClaims.map<ClaimModel>((c) {
            final tranche1 = _asInt(c['tranche1']);
            final tranche2 = _asInt(c['tranche2']);
            final gross = _asInt(c['gross_payout']);
            return ClaimModel(
              id: c['id'] as String,
              type: _triggerLabel(c['trigger_type'] as String),
              date: _formatDate(c['created_at'] as String?),
              amount: gross,
              status: c['status'] as String,
              zone: c['zone'] as String,
              icon: _triggerIcon(c['trigger_type'] as String),
              grossAmount: gross,
              immediateAmount: tranche1,
              heldAmount: tranche2,
            );
          }).toList();
        }
      } // end !hasDemoData guard

      // Fetch active policy
      final policy = await ApiService.getPolicyDocument(userId);
      if (policy != null) {
        // Persist the policy ID for later use
        final pid = policy['id'] as String? ?? '';
        if (pid.isNotEmpty) await StorageService.setPolicyId(pid);

        activePolicy = PolicyModel(
          plan: _planLabel(policy['plan_tier'] as String),
          premium: _asInt(policy['weekly_premium']),
          status: (policy['status'] as String).toUpperCase(),
          coverageStart: _formatDate(policy['start_date'] as String?),
          coverageEnd: _formatDate(null, addDays: 365),
          riders: [],
          coverageDescription: 'Rain, heat, pollution, AQI > 200',
        );
        // Update premium breakdown with real API values
        premiumBreakdown = PremiumBreakdownModel(
          baseRate: _asInt(policy['base_premium']),
          finalRate: _asInt(policy['weekly_premium']),
          factors: [
            PremiumBreakdownFactor(factor: "Base rate (${_planLabel(policy['plan_tier'])})", adjustment: _asInt(policy['base_premium']), reason: "—"),
            PremiumBreakdownFactor(factor: "Zone risk adjustment", adjustment: _asInt(policy['zone_adjustment']), reason: "Based on your zone"),
          ],
          comparison: [
            PremiumComparison(zone: "Velachery", rate: 55),
            PremiumComparison(zone: "Your zone", rate: _asInt(policy['weekly_premium'])),
            PremiumComparison(zone: "Anna Nagar", rate: 34),
          ],
        );
      }

      // Fetch live disruptions for the user's zone (last 24hrs → show alert card)
      if (worker.zone.isNotEmpty) {
        final disruptions =
            await ApiService.getDisruptionEvents(worker.zone);
        if (disruptions.isNotEmpty) {
          final latest = disruptions.first as Map<String, dynamic>;
          final startedAt = latest['started_at'] as String?;
          final isRecent = startedAt != null &&
              DateTime.now().difference(DateTime.parse(startedAt)).inHours < 24;
          if (isRecent && activeDisruption == null) {
            final tType = latest['trigger_type'] as String? ?? 'disruption';
            activeDisruption = ActiveDisruption(
              triggerName: _triggerLabel(tType),
              triggerIcon: tType.contains('rain') ? 'rain' : (tType.contains('heat') ? 'heat' : 'app'),
              message: '${_triggerLabel(tType)} active in your zone',
              payoutExpected: 0,
              creditDate: 'Auto-disbursed upon confirmation',
              isActive: true,
            );
          }
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[MockDataService] API hydration error: $e');
      // App still works with local/mock data on failure
    }
  }

  // ── Demo triggers (now hits the real API) ─────────────────────────────────

  void triggerRainDisruption() => _triggerClaim(
    type: 'Rain',
    message: 'Rain disruption in your zone',
    triggerType: 'rain_heavy',
    severity: 1.0,
    durationHours: 3,
  );

  void triggerPlatformDowntime() => _triggerClaim(
    type: 'Downtime',
    message: 'Platform outage in your zone',
    triggerType: 'platform_outage',
    severity: 0.9,
    durationHours: 2,
  );

  void triggerExtremeHeat() => _triggerClaim(
    type: 'Heat',
    message: 'Extreme heat alert in your zone',
    triggerType: 'heat_severe',
    severity: 0.8,
    durationHours: 3,
  );

  void triggerInternetBlackout() => _triggerClaim(
    type: 'Internet Blackout',
    message: 'Regional internet service disruption detected',
    triggerType: 'internet_blackout',
    severity: 0.7,
    durationHours: 4,
  );

  void triggerCompoundDisruption() {
    final userId = StorageService.userId;
    final tempId = 'CLM_CMPD_${DateTime.now().millisecondsSinceEpoch}';
    final payout = 245; // Compound rate

    activeDisruption = ActiveDisruption(
      triggerName: 'Compound Trigger',
      triggerIcon: 'app',
      message: 'Multiple disruptions detected (Platform + Rain)',
      payoutExpected: payout,
      creditDate: "Credited instantly",
      isActive: true,
    );

    claims.insert(0, ClaimModel(
      id: tempId,
      type: 'Compound (Platform + Rain)',
      date: 'Just now',
      amount: payout,
      status: 'APPROVED',
      zone: worker.zone,
      icon: 'app',
      grossAmount: payout,
      immediateAmount: (payout * 0.7).round(),
      heldAmount: (payout * 0.3).round(),
    ));

    walletBalance += payout;
    monthlySavings += payout;
    transactions.insert(0, {
      'type': 'credit',
      'title': 'Compound Payout',
      'subtitle': 'Platform + Rain · ${worker.zone}',
      'amount': payout,
      'date': 'Just now',
    });

    _persistDemoState();
    notifyListeners();
    AppEvents.instance.claimUpdated();
    AppEvents.instance.walletUpdated();
  }

  void triggerFraudAttempt() {
    final tempId = 'CLM_FRAUD_${DateTime.now().millisecondsSinceEpoch}';
    final payout = 200; // Provisional credit

    claims.insert(0, ClaimModel(
      id: tempId,
      type: 'Rain Disruption',
      date: 'Just now',
      amount: payout,
      status: 'FLAGGED',
      zone: worker.zone,
      icon: 'rain',
      frsScore: 87, // High fraud score
      grossAmount: 450,
      immediateAmount: 200,
      heldAmount: 250,
    ));

    walletBalance += payout;
    transactions.insert(0, {
      'type': 'credit',
      'title': 'Provisional Payout',
      'subtitle': 'Pending investigation · ${worker.zone}',
      'amount': payout,
      'date': 'Just now',
    });

    _persistDemoState();
    notifyListeners();
    AppEvents.instance.claimUpdated();
    AppEvents.instance.walletUpdated();
  }

  void creditWalletForDemo({
    required int amount,
    required String title,
    required String subtitle,
    bool addToSavings = false,
  }) {
    walletBalance += amount;
    if (addToSavings) monthlySavings += amount;
    
    transactions.insert(0, {
      'type': 'credit',
      'title': title,
      'subtitle': subtitle,
      'amount': amount,
      'date': 'Just now',
    });

    _persistDemoState();
    notifyListeners();
    AppEvents.instance.walletUpdated();
  }

  void _triggerClaim({
    required String type,
    required String message,
    required String triggerType,
    required double severity,
    required double durationHours,
  }) {
    final userId = StorageService.userId;

    // Show active disruption banner immediately
    activeDisruption = ActiveDisruption(
      triggerName: type,
      triggerIcon: triggerType.contains('rain') ? 'rain' : (triggerType.contains('heat') ? 'heat' : 'app'),
      message: message,
      payoutExpected: 0,
      creditDate: "Credited instantly",
      isActive: true,
    );

    // Add a PENDING claim optimistically
    final tempId = 'CLM_PENDING_${DateTime.now().millisecondsSinceEpoch}';
    claims.insert(0, ClaimModel(
      id: tempId,
      type: _triggerLabel(triggerType),
      date: 'Just now',
      amount: 0,
      status: 'PENDING',
      zone: worker.zone,
      icon: _triggerIcon(triggerType),
    ));
    notifyListeners();
    
    // ALWAYS bypass real API for demo controls to ensure optimistic UI consistency.
    final payout = switch (triggerType) {
      'rain_heavy' => 120,    // README: ₹120
      'platform_outage' => 140, // README: ₹140
      'heat_severe' => 130,   // README: ₹130
      _ => 100,
    };
    claims.first.status = 'APPROVED';
    if (claims.first.id == tempId) {
      claims[0] = ClaimModel(
        id: tempId, type: _triggerLabel(triggerType),
        date: 'Just now', amount: payout, status: 'APPROVED',
        zone: worker.zone, icon: _triggerIcon(triggerType),
        grossAmount: payout, immediateAmount: (payout * 0.7).round(),
        heldAmount: (payout * 0.3).round(),
      );
    }
    walletBalance += payout;
    monthlySavings += payout;
    transactions.insert(0, {
      'type': 'credit',
      'title': '${_triggerLabel(triggerType)} Payout',
      'subtitle': 'Auto-triggered · ${worker.zone}',
      'amount': payout,
      'date': 'Just now',
    });
    // Notify ClaimsBloc via the demo bridge so BLoC state stays in sync.
    onClaimApproved?.call(domain.Claim(
      id: tempId,
      userId: '',
      triggerType: triggerType,
      displayLabel: _triggerLabel(triggerType),
      status: domain.ClaimStatus.approved,
      grossPayout: payout,
      tranche1: (payout * 0.7).round(),
      tranche2: (payout * 0.3).round(),
      zone: worker.zone,
      createdAt: DateTime.now(),
    ));

    _persistDemoState(); // ← save so it survives refresh
    notifyListeners();
    
    // Fire global events so all screens (Dashboard, Wallet) reload INSTANTLY
    AppEvents.instance.claimUpdated();
    AppEvents.instance.walletUpdated();
  }

  void activatePolicy(String tier) {
    hasActivePolicy = true;
    _updateActivePolicyModel(tier);
    notifyListeners();
    _persistDemoState();
    AppEvents.instance.policyUpdated();
  }

  void _updateActivePolicyModel(String tier) {
    final premium = tier == 'full' ? 79 : (tier == 'basic' ? 35 : 49);
    activePolicy = PolicyModel(
      plan: _planLabel(tier),
      premium: premium,
      status: "ACTIVE",
      coverageStart: _formatDate(DateTime.now().toIso8601String()),
      coverageEnd: _formatDate(DateTime.now().add(const Duration(days: 91)).toIso8601String()),
      riders: tier == 'standard' ? ["Bandh / Curfew", "Internet Blackout"] : [],
      coverageDescription: tier == 'full'
          ? "All 9 triggers + compound disruptions covered"
          : (tier == 'standard'
              ? "Rain, heat, pollution, bandh, and internet blackout covered"
              : "Rain and heat only"),
    );
  }

  // ── Wallet ─────────────────────────────────────────────────────────────────

  void withdrawToUPI(int amount, String upiId) {
    if (amount <= 0 || walletBalance < amount) return;

    final userId = StorageService.userId;

    // Optimistic UI update
    walletBalance -= amount;
    transactions.insert(0, {
      'type': 'debit',
      'title': 'UPI Withdrawal',
      'subtitle': upiId,
      'amount': amount,
      'date': 'Just now',
    });
    notifyListeners();

    if (userId.isEmpty) return;

    ApiService.walletDebit(
      userId: userId,
      amount: amount,
      description: 'UPI Withdrawal',
      reference: upiId,
    ).then((_) {
      // Success — optimistic UI already applied
    }).onError((e, _) {
      debugPrint('[MockDataService] walletDebit error: $e');
      // Revert on failure
      walletBalance += amount;
      transactions.removeAt(0);
      notifyListeners();
    });
  }

  // ── Misc UI helpers ────────────────────────────────────────────────────────

  void rotateNudge() {
    currentNudgeIndex = (currentNudgeIndex + 1) % nudges.length;
    notifyListeners();
  }

  void dismissDisruption() {
    activeDisruption = null;
    notifyListeners();
  }

  void dismissPredictiveNudge() {
    showPredictiveNudge = false;
    notifyListeners();
  }

  void resetDemo() {
    walletBalance = 0;
    monthlySavings = 0;
    activeDisruption = null;
    showPredictiveNudge = true;
    claims = [];
    transactions = [];
    // Clear persisted demo state from Hive so restart also resets cleanly
    final box = _appDataBoxOrNull();
    box?.delete('demo_walletBalance');
    box?.delete('demo_monthlySavings');
    box?.delete('demo_transactions');
    box?.delete('demo_claims');
    notifyListeners();
    final userId = StorageService.userId;
    if (userId.isNotEmpty) _hydrateFromApi(userId);

    // Dynamic Tracking Bridge
    LocationService.instance.addListener(_onLocationChanged);
  }

  void _onLocationChanged() {
    final liveZone = LocationService.instance.currentZone;
    if (liveZone != "Unknown Zone" && liveZone != "Outside Service Area" && liveZone != worker.zone) {
      int newIss = worker.issScore;
      
      // Update Risk Profile based on Zone
      if (liveZone.contains('Adyar') || liveZone.contains('Velachery')) {
        // High Rain Risk Area
        liveStatuses[0] = LiveStatusModel(icon: "rain", name: "Rain", level: 0.9, statusText: "72mm/hr · CRITICAL · IMD");
        liveStatuses[1] = LiveStatusModel(icon: "heat", name: "Heat", level: 0.2, statusText: "32°C · Moderate");
        newIss = (newIss + 15).clamp(0, 100);
      } else if (liveZone.contains('HSR') || liveZone.contains('Koramangala')) {
        // Platform Downtime Risk Area
        liveStatuses[2] = LiveStatusModel(icon: "app", name: "Outage", level: 0.8, statusText: "Zomato/Swiggy API Lag High");
        newIss = (newIss + 10).clamp(0, 100);
      } else if (liveZone.contains('Kattankulathur')) {
        // Kattankulathur Specific: High Temperature / Sunstroke Risk
        liveStatuses[0] = LiveStatusModel(icon: "rain", name: "Rain", level: 0.05, statusText: "Clear Skies");
        liveStatuses[1] = LiveStatusModel(icon: "heat", name: "Heat", level: 0.85, statusText: "41°C · Extreme Heat · IMD Alert");
        liveStatuses[2] = LiveStatusModel(icon: "app", name: "Outage", level: 0.1, statusText: "Networks Stable");
        newIss = (newIss + 5).clamp(0, 100);
      } else {
        // Clear Zone
        liveStatuses[0] = LiveStatusModel(icon: "rain", name: "Rain", level: 0.1, statusText: "Clear Skies");
        liveStatuses[1] = LiveStatusModel(icon: "heat", name: "Heat", level: 0.3, statusText: "34°C · Normal");
        liveStatuses[2] = LiveStatusModel(icon: "app", name: "Outage", level: 0.05, statusText: "Platforms Stable");
      }
      notifyListeners();
      _persistDemoState();
    }
  }

  // ── Persona Switching ──────────────────────────────────────────────────────

  Future<void> switchPersona(String personaId) async {
    // 1. Reset current state
    walletBalance = 0;
    monthlySavings = 0;
    claims = [];
    transactions = [];
    activeDisruption = null;
    
    // Reset ML defaults
    simulateHighIss = true;
    forceFraudFlag = false;

    // 2. Apply persona-specific state
    switch (personaId) {
      case 'karthik':
        worker = WorkerModel(id: 'DEMO_KARTHIK', name: 'Karthik Shetty', platform: 'Zepto', city: 'Chennai', zone: 'Adyar', weeklyIncomeEstimate: 4200, issScore: 78);
        activePolicy = PolicyModel(plan: 'Standard Shield', premium: 49, status: 'ACTIVE', coverageStart: _formatDate(DateTime.now().toIso8601String()), coverageEnd: _formatDate(DateTime.now().add(const Duration(days: 91)).toIso8601String()), riders: [], coverageDescription: 'Rain, heat, outage, AQI covered');
        LocationService.instance.forceMockLocation('Adyar Dark Store Zone', 13.0067, 80.2206, depthScore: 0.92);
        spoofedZone = 'Adyar Dark Store Zone';
        break;
      case 'ravi':
        worker = WorkerModel(id: 'DEMO_RAVI', name: 'Ravi Kumar', platform: 'Zepto', city: 'Chennai', zone: 'Velachery', weeklyIncomeEstimate: 5500, issScore: 84);
        activePolicy = PolicyModel(plan: 'Full Shield', premium: 79, status: 'ACTIVE', coverageStart: _formatDate(DateTime.now().toIso8601String()), coverageEnd: _formatDate(DateTime.now().add(const Duration(days: 91)).toIso8601String()), riders: [], coverageDescription: 'All perturbations + compound triggers');
        LocationService.instance.forceMockLocation('Velachery Dark Store Zone', 12.9815, 80.2180, depthScore: 0.88);
        spoofedZone = 'Velachery Dark Store Zone';
        break;
      case 'priya':
        worker = WorkerModel(id: 'DEMO_PRIYA', name: 'Priya Mani', platform: 'Zepto', city: 'Chennai', zone: 'T.Nagar', weeklyIncomeEstimate: 3800, issScore: 65);
        activePolicy = PolicyModel(plan: 'Basic Shield', premium: 35, status: 'ACTIVE', coverageStart: _formatDate(DateTime.now().toIso8601String()), coverageEnd: _formatDate(DateTime.now().add(const Duration(days: 91)).toIso8601String()), riders: [], coverageDescription: 'Rain and Heat only');
        LocationService.instance.forceMockLocation('T Nagar Dark Store Zone', 13.0418, 80.2341, depthScore: 0.65);
        spoofedZone = 'T Nagar Dark Store Zone';
        break;
      case 'muthu':
        worker = WorkerModel(id: 'DEMO_MUTHU', name: 'Muthu R', platform: 'Zepto', city: 'Chennai', zone: 'Tambaram', weeklyIncomeEstimate: 3200, issScore: 45);
        activePolicy = PolicyModel(plan: 'No Policy', premium: 0, status: 'INACTIVE', coverageStart: '', coverageEnd: '', riders: [], coverageDescription: '');
        hasActivePolicy = false;
        LocationService.instance.forceMockLocation('Tambaram Dark Store Zone', 12.9249, 80.1000, depthScore: 0.85);
        spoofedZone = 'Tambaram Dark Store Zone';
        break;
      case 'fraudster':
        worker = WorkerModel(id: 'DEMO_FRAUDSTER', name: 'Unknown User', platform: 'Zepto', city: 'Chennai', zone: 'Adyar', weeklyIncomeEstimate: 4000, issScore: 20);
        activePolicy = PolicyModel(plan: 'Standard Shield', premium: 49, status: 'ACTIVE', coverageStart: _formatDate(DateTime.now().toIso8601String()), coverageEnd: _formatDate(DateTime.now().add(const Duration(days: 91)).toIso8601String()), riders: [], coverageDescription: '');
        LocationService.instance.forceMockLocation('Adyar Dark Store Zone', 13.0067, 80.2206, depthScore: 0.1);
        spoofedZone = 'Adyar Dark Store Zone';
        break;
      case 'santhosh':
        worker = WorkerModel(id: 'DEMO_SANTHOSH', name: 'Santhosh', platform: 'Zepto', city: 'Chennai', zone: 'Anna Nagar', weeklyIncomeEstimate: 4500, issScore: 92);
        activePolicy = PolicyModel(plan: 'Basic Shield', premium: 35, status: 'ACTIVE', coverageStart: _formatDate(DateTime.now().toIso8601String()), coverageEnd: _formatDate(DateTime.now().add(const Duration(days: 91)).toIso8601String()), riders: [], coverageDescription: '');
        LocationService.instance.forceMockLocation('Anna Nagar Dark Store Zone', 13.0850, 80.2101, depthScore: 0.95);
        spoofedZone = 'Anna Nagar Dark Store Zone';
        break;
    }
    
    // 3. Synchronize global StorageService so all other screens (Dashboard, Wallet) 
    // recognize the new persona ID as the primary user.
    if (worker.id.isNotEmpty) {
      await StorageService.setUserId(worker.id);
      await StorageService.setLoggedIn(true);
      await StorageService.setUserZone(worker.zone);
      
      final box = _appDataBoxOrNull();
      await box?.put('isDemoSession', true);
    }

    await _persistDemoState();
    notifyListeners();
    
    // Fire events to notify other parts of the app that data has changed
    AppEvents.instance.profileUpdated();
    AppEvents.instance.policyUpdated();
    AppEvents.instance.walletUpdated();
    AppEvents.instance.claimUpdated();
  }

  void updateIssAndPricing(int newIss, double newPremium) {
    worker = worker.copyWith(issScore: newIss);
    activePolicy = activePolicy.copyWith(premium: newPremium.round());
    
    // Add to history for chart
    issHistory.add(newIss.toDouble());
    if (issHistory.length > 10) issHistory.removeAt(0);

    notifyListeners();
    _persistDemoState();
    AppEvents.instance.profileUpdated();
    AppEvents.instance.policyUpdated();
  }

  void updateMlToggles({bool? iss, bool? fraud}) {
    if (iss != null) simulateHighIss = iss;
    if (fraud != null) forceFraudFlag = fraud;
    notifyListeners();
    AppEvents.instance.profileUpdated();
  }

  void updateSpoofedLocation(String zone) {
    spoofedZone = zone;
    final centroid = LocationService.ZONE_CENTROIDS[zone];
    if (centroid != null) {
      LocationService.instance.forceMockLocation(zone, centroid['lat']!, centroid['lon']!, depthScore: 0.95);
    }
    notifyListeners();
    AppEvents.instance.profileUpdated();
  }

  /// Clear ALL mock data and restore app to pristine state
  void clearAllMockData() {
    // Reset worker state
    worker = WorkerModel(
      id: '',
      name: '',
      platform: '',
      city: '',
      zone: '',
      weeklyIncomeEstimate: 0,
      issScore: 62,
    );

    // Reset policy
    activePolicy = PolicyModel(
      plan: "Standard Shield",
      premium: 49,
      status: "INACTIVE",
      coverageStart: "",
      coverageEnd: "",
      riders: [],
      coverageDescription: "",
    );

    // Clear all financial data
    walletBalance = 0;
    monthlySavings = 0;
    totalPremiums = 0;
    potentialLoss = 0;
    
    // Clear claims and transactions
    claims = [];
    transactions = [];
    
    // Clear disruptions
    activeDisruption = null;
    
    // Reset all overrides
    simulateHighIss = true;
    forceFraudFlag = false;
    spoofedZone = null;
    FraudSensorService.mockFraudSpoofing = false;
    
    // Reset UI state
    showPredictiveNudge = false;
    showShadowNudge = false;
    missedAmount = 0;
    missedEventsCount = 0;
    currentNudgeIndex = 0;
    
    // Clear location override
    LocationService.instance.clearMockLocation();
    
    // Clear persisted demo state from storage
    final box = _appDataBoxOrNull();
    box?.delete('demo_walletBalance');
    box?.delete('demo_monthlySavings');
    box?.delete('demo_transactions');
    box?.delete('demo_claims');
    box?.delete('demo_activeDisruption');
    
    // Reset ISS history
    issHistory = [55, 60, 52, 68, 58, 62];
    
    // Reset live statuses to neutral
    liveStatuses = [
      LiveStatusModel(icon: "rain", name: "Rain", level: 0.0, statusText: "No rain · Normal"),
      LiveStatusModel(icon: "heat", name: "Heat Wave", level: 0.3, statusText: "Normal · 32°C"),
      LiveStatusModel(icon: "downtime", name: "Platform", level: 0.05, statusText: "Operational · 99% uptime"),
      LiveStatusModel(icon: "internet", name: "Internet", level: 0.0, statusText: "Stable · 40+ Mbps"),
      LiveStatusModel(icon: "strike", name: "Bandh/Strike", level: 0.0, statusText: "No alerts"),
    ];
    
    // Notify all listeners
    notifyListeners();
    LocationService.instance.notifyListeners();
    
    // Fire update events
    AppEvents.instance.profileUpdated();
    AppEvents.instance.walletUpdated();
    AppEvents.instance.claimUpdated();
    AppEvents.instance.policyUpdated();
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  static String _formatDate(String? isoString, {int addDays = 0}) {
    try {
      if (isoString == null) {
        final d = DateTime.now().add(Duration(days: addDays));
        return '${d.day} ${_month(d.month)} ${d.year}';
      }
      final d = DateTime.parse(isoString).add(Duration(days: addDays));
      return '${d.day} ${_month(d.month)} ${d.year}';
    } catch (_) {
      return isoString ?? '';
    }
  }

  static String _month(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ][m];
}
