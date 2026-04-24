import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

enum ApiStatus { unknown, online, offline, degraded }

class ServiceHealth {
  final String name;
  final String description;
  final String category;
  final ApiStatus status;
  final int? latencyMs;
  final String? detail;

  const ServiceHealth({
    required this.name,
    required this.description,
    required this.category,
    required this.status,
    this.latencyMs,
    this.detail,
  });
}

class ApiHealthService extends ChangeNotifier {
  static final ApiHealthService instance = ApiHealthService._internal();
  ApiHealthService._internal();

  List<ServiceHealth> _services = [];
  bool _isChecking = false;
  DateTime? _lastChecked;
  Timer? _autoRefreshTimer;

  List<ServiceHealth> get services => List.unmodifiable(_services);
  bool get isChecking => _isChecking;
  DateTime? get lastChecked => _lastChecked;

  ApiStatus get overallStatus {
    if (_services.isEmpty) return ApiStatus.unknown;
    final online = _services.where((s) => s.status == ApiStatus.online).length;
    if (online == _services.length) return ApiStatus.online;
    if (online == 0) return ApiStatus.offline;
    return ApiStatus.degraded;
  }

  List<String> get categories => _services
      .map((s) => s.category)
      .fold<List<String>>([], (acc, c) => acc.contains(c) ? acc : [...acc, c]);

  List<ServiceHealth> forCategory(String cat) =>
      _services.where((s) => s.category == cat).toList();

  void startAutoRefresh() {
    checkAll();
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => checkAll());
  }

  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  Future<void> checkAll() async {
    if (_isChecking) return;
    _isChecking = true;
    notifyListeners();

    // First: try to get real-time status from backend's /health/services endpoint
    Map<String, dynamic> backendStatus = {};
    int? backendLatency;
    ApiStatus backendApiStatus = ApiStatus.offline;

    try {
      final sw = Stopwatch()..start();
      final res = await http
          .get(Uri.parse('${ApiService.baseUrl}/health'))
          .timeout(const Duration(seconds: 65)); // Render free-tier cold start up to 60s
      sw.stop();
      backendLatency = sw.elapsedMilliseconds;

      if (res.statusCode == 200) {
        backendApiStatus = ApiStatus.online;

        // Now fetch the per-service breakdown
        try {
          final svcRes = await http
              .get(Uri.parse('${ApiService.baseUrl}/health/services'))
              .timeout(const Duration(seconds: 65)); // same cold-start buffer
          if (svcRes.statusCode == 200) {
            backendStatus = jsonDecode(svcRes.body) as Map<String, dynamic>;
          }
        } catch (_) {}
      }
    } catch (_) {
      backendApiStatus = ApiStatus.offline;
    }

    final failures = backendStatus['_failures'] as Map<String, dynamic>? ?? {};

    ServiceHealth fromBackend({
      required String name,
      required String description,
      required String category,
      required String key,
    }) {
      if (backendApiStatus == ApiStatus.offline) {
        return ServiceHealth(
          name: name, description: description, category: category,
          status: ApiStatus.unknown, detail: 'Backend unreachable',
        );
      }
      final raw = backendStatus[key];
      final failCount = (failures[key] as num?)?.toInt() ?? 0;
      ApiStatus st;
      String detail;
      if (raw == null) {
        st = ApiStatus.unknown; detail = 'Not reported';
      } else if (raw == 'ok') {
        st = failCount > 0 ? ApiStatus.degraded : ApiStatus.online;
        detail = failCount > 0 ? '$failCount recent failures — healthy' : 'Live';
      } else if (raw == 'degraded') {
        st = ApiStatus.degraded; detail = 'Using fallback cache (${failCount}x failed)';
      } else if (raw == 'missing_key') {
        st = ApiStatus.offline; detail = 'API key not configured in .env';
      } else {
        st = ApiStatus.offline; detail = raw.toString();
      }
      return ServiceHealth(
        name: name, description: description, category: category,
        status: st, detail: detail,
      );
    }

    ServiceHealth maxMindFromBackend() {
      const cat = 'Intelligence';
      const desc =
          'IP geolocation for fraud (GeoIP2 web) — MAXMIND_ACCOUNT_ID + MAXMIND_LICENSE_KEY';
      if (backendApiStatus == ApiStatus.offline) {
        return const ServiceHealth(
          name: 'MaxMind GeoIP',
          description: desc,
          category: cat,
          status: ApiStatus.unknown,
          detail: 'Backend unreachable',
        );
      }
      final raw = backendStatus['maxmind']?.toString();
      if (raw == 'ok') {
        return const ServiceHealth(
          name: 'MaxMind GeoIP',
          description: desc,
          category: cat,
          status: ApiStatus.online,
          detail: 'Live',
        );
      }
      if (raw == 'partial_key') {
        return const ServiceHealth(
          name: 'MaxMind GeoIP',
          description: desc,
          category: cat,
          status: ApiStatus.degraded,
          detail: 'Set both MAXMIND_ACCOUNT_ID and MAXMIND_LICENSE_KEY',
        );
      }
      if (raw == 'missing_key') {
        return const ServiceHealth(
          name: 'MaxMind GeoIP',
          description: desc,
          category: cat,
          status: ApiStatus.offline,
          detail: 'MaxMind credentials not set in .env',
        );
      }
      return ServiceHealth(
        name: 'MaxMind GeoIP',
        description: desc,
        category: cat,
        status: ApiStatus.unknown,
        detail: raw ?? 'Not reported',
      );
    }

    ServiceHealth ooklaInternetFromBackend() {
      const cat = 'Weather & Environment';
      const desc =
          'Optional paid Ookla Enterprise zone health — OOKLA_API_KEY + USE_OOKLA_INTERNET=true (default: inferred)';
      if (backendApiStatus == ApiStatus.offline) {
        return const ServiceHealth(
          name: 'Ookla internet (optional)',
          description: desc,
          category: cat,
          status: ApiStatus.unknown,
          detail: 'Backend unreachable',
        );
      }
      final raw = backendStatus['ookla_internet']?.toString() ?? '';
      if (raw == 'enterprise_live') {
        return const ServiceHealth(
          name: 'Ookla internet (optional)',
          description: desc,
          category: cat,
          status: ApiStatus.online,
          detail: 'Enterprise API enabled',
        );
      }
      if (raw == 'inferred_only') {
        return const ServiceHealth(
          name: 'Ookla internet (optional)',
          description: desc,
          category: cat,
          status: ApiStatus.online,
          detail: 'Inferred connectivity (default — no Ookla billing)',
        );
      }
      if (raw == 'key_present_opt_in_disabled') {
        return const ServiceHealth(
          name: 'Ookla internet (optional)',
          description: desc,
          category: cat,
          status: ApiStatus.degraded,
          detail: 'OOKLA_API_KEY set — set USE_OOKLA_INTERNET=true to call API',
        );
      }
      return ServiceHealth(
        name: 'Ookla internet (optional)',
        description: desc,
        category: cat,
        status: ApiStatus.unknown,
        detail: raw.isEmpty ? 'Not reported' : raw,
      );
    }

    _services = [
      // ── Core Backend ─────────────────────────────────────────────────────
      ServiceHealth(
        name: 'Backend (Express)',
        description: 'Node.js server on localhost:3000 — all routes',
        category: 'Core Backend',
        status: backendApiStatus,
        latencyMs: backendLatency,
        detail: backendApiStatus == ApiStatus.online
            ? '${backendLatency}ms'
            : 'Unreachable — run: node src/index.js',
      ),
      fromBackend(
        name: 'Supabase (PostgreSQL)',
        description: 'Auth, workers, policies, claims, wallet — SUPABASE_URL',
        category: 'Core Backend',
        key: 'supabase',
      ),

      // ── Weather & Environment ─────────────────────────────────────────────
      fromBackend(
        name: 'OpenWeatherMap',
        description: 'Rainfall mm/hr · Temperature °C · Conditions — OWM_API_KEY',
        category: 'Weather & Environment',
        key: 'weather',
      ),
      fromBackend(
        name: 'AQICN',
        description: 'Air quality index · PM2.5 · Station data — AQICN_API_KEY',
        category: 'Weather & Environment',
        key: 'aqi',
      ),
      fromBackend(
        name: 'OpenRouteService (Traffic)',
        description: 'Route gridlock detection for zone disruptions — OPENROUTE_API_KEY',
        category: 'Weather & Environment',
        key: 'traffic',
      ),
      ooklaInternetFromBackend(),

      // ── Intelligence ──────────────────────────────────────────────────────
      fromBackend(
        name: 'NewsAPI',
        description: 'Bandh / strike NLP scraper — NEWSAPI_KEY',
        category: 'Intelligence',
        key: 'news',
      ),
      fromBackend(
        name: 'Cell Tower API',
        description: 'Network connectivity verification — CELL_LOCATION_API_KEY',
        category: 'Intelligence',
        key: 'cell_tower',
      ),
      fromBackend(
        name: 'OpenCelliD',
        description: 'Optional cell-to-location (tried first in /workers/cell-locate) — OPENCELLID_API_KEY',
        category: 'Intelligence',
        key: 'opencellid',
      ),
      maxMindFromBackend(),

      // ── Payments & Notifications ──────────────────────────────────────────

      fromBackend(
        name: 'Firebase Messaging',
        description: 'Push notifications for claim updates — FIREBASE_SERVER_KEY',
        category: 'Payments & Notifications',
        key: 'firebase',
      ),
    ];

    _lastChecked = DateTime.now();
    _isChecking = false;
    notifyListeners();

    final onlineCount = _services.where((s) => s.status == ApiStatus.online).length;
    debugPrint('[ApiHealth] ${_services.length} services — $onlineCount online, overall: ${overallStatus.name}');
  }
}
