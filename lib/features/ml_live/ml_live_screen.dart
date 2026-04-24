import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../../services/storage_service.dart';

class MLLiveScreen extends StatefulWidget {
  const MLLiveScreen({super.key});

  @override
  State<MLLiveScreen> createState() => _MLLiveScreenState();
}

class _MLLiveScreenState extends State<MLLiveScreen> {
  
  Map<String, dynamic> _issResult    = {};
  Map<String, dynamic> _fraudResult  = {};
  Map<String, dynamic> _premiumResult = {};
  Map<String, dynamic> _forecastResult = {};
  bool _loading = false;
  bool _issLoading = false;
  bool _forecastLoading = false;
  
  String get _mlUrl => ApiService.mlBackendUrl;

  Future<String> _userCity() async =>
      await StorageService.instance.getUserCity() ?? 'Chennai';

  Future<String> _userZone() async =>
      await StorageService.instance.getUserZone() ?? 'Adyar';

  String _zoneSlug(String zone) => zone
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  @override
  void initState() {
    super.initState();
    _runAllModels();
  }

  Future<void> _runAllModels() async {
    setState(() => _loading = true);
    
    await Future.wait([
      _runISS(),
      _runFraud(),
      _runPremium(),
      _runForecast(),
    ]);
    
    setState(() => _loading = false);
  }

  Future<void> _runISS() async {
    setState(() => _issLoading = true);
    
    final city = await _userCity();
    final endpoints = [
      '$_mlUrl/iss',
    ];
    
    for (final endpoint in endpoints) {
      try {
        final res = await http.post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'zone_flood_risk':       0.75,
            'avg_daily_income':      600.0,
            'disruption_freq_12mo':  8,
            'claims_history_penalty': 2.0,
            'bandh_freq_zone': 1.0,
            'platform_outage_per_mo': 0.5,
            'coastal_zone': true,
            'city': city,
            'use_ml': true,
          }),
        ).timeout(const Duration(seconds: 8));
        
        if (res.statusCode == 200) {
          final data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
          setState(() {
            _issResult = {
              ...data,
              'tier': data['risk_band'],
              'recommendation': data['recommended_tier'],
            };
            _issLoading = false;
          });
          print('[ML] ISS from $endpoint: $data');
          return;
        }
        print('[ML] ISS endpoint $endpoint returned ${res.statusCode}');
      } catch (e) {
        print('[ML] ISS endpoint $endpoint failed: $e');
      }
    }
    
    // All endpoints failed — use computed mock
    // Run the rule engine locally in Dart as fallback
    final score = _calculateISSLocally();
    setState(() {
      _issResult = {
        'iss_score':      score,
        'risk_band': score >= 70 ? 'LOW' : score >= 50 ? 'MEDIUM' : 'HIGH',
        'recommended_tier': score >= 70 ? 'Basic Shield' : score >= 50 ? 'Standard Shield' : 'Full Shield',
        'tier': score >= 70 ? 'LOW' : score >= 50 ? 'MEDIUM' : 'HIGH',
        'recommendation': score >= 70 ? 'Basic Shield' : score >= 50 ? 'Standard Shield' : 'Full Shield',
        '_mock': true,
        '_source': 'local_rule_engine',
      };
      _issLoading = false;
    });
  }

  int _calculateISSLocally() {
    // Same formula as Python service — run locally as fallback
    double score = 100;
    score -= 0.75 * 20;    // zone_flood_risk
    score -= 8;            // disruption_freq (min 15)
    score += 600 / 200;    // income bonus
    score += 4 / 10;       // tenure bonus
    score -= 3;            // Chennai city adjustment
    return score.clamp(0, 100).round();
  }

  Future<void> _runFraud() async {
    final city = await _userCity();
    try {
      final res = await http.post(
        Uri.parse('$_mlUrl/fraud'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'gps_zone_mismatch': 0,
          'wifi_home_ssid': 0,
          'battery_charging': 0,
          'accelerometer_idle': 0,
          'platform_app_inactive': 0,
          'ip_home_match': 0,
          'claim_latency_under30s': 0,
          'gps_jitter_perfect': 0,
          'barometer_mismatch': 0,
          'hw_fingerprint_match': 0,
          'app_install_cluster': 0,
          'days_since_onboard': 45,
          'referral_depth': 1,
          'simultaneous_zone_claims': 2,
          'zone_depth_score': 0.84,
          'iss_score': (_issResult['iss_score'] as num?)?.toInt() ?? 62,
          'has_real_disruption': 0,
          'claim_city': city,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (res.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        setState(() => _fraudResult = {
          ...data,
          'anomaly_score': data['fps_score'],
          'is_anomalous': (data['action'] ?? '').toString() != 'AUTO_APPROVE',
          'top_features': [data['reason'] ?? data['fps_tier'] ?? 'zone_depth_score'],
        });
      }
    } catch (e) {
      setState(() => _fraudResult = {
        'fps_score': 0.14,
        'fps_tier': 'GREEN',
        'action': 'AUTO_APPROVE',
        'anomaly_score': 0.14,
        'is_anomalous': false,
        'top_features': ['fps_tier'],
        '_mock': true,
      });
    }
  }

  Future<void> _runPremium() async {
    final userZone = await _userZone();
    try {
      final res = await http.post(
        Uri.parse('$_mlUrl/premium'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'plan_tier': 'standard',
          'zone': userZone,
          'iss_score': _issResult['iss_score'] ?? 62,
          'previous_premium': 49.0,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (res.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
        final base = ((data['base_premium'] ?? 49) as num).toDouble();
        final finalPremium = ((data['final_premium'] ?? base) as num).toDouble();
        setState(() => _premiumResult = {
          ...data,
          'zone_adjustment': (data['zone_adjustment'] as num?) ?? (finalPremium - base),
        });
      }
    } catch (e) {
      setState(() => _premiumResult = {
        'final_premium': 54, 'base_premium': 49,
        'zone_adjustment': 5, '_mock': true,
      });
    }
  }

  Future<void> _runForecast() async {
    setState(() => _forecastLoading = true);
    final userZone = await _userZone();
    final city = await _userCity();
    final endpoints = [
      '$_mlUrl/forecast/${Uri.encodeComponent(_zoneSlug(userZone))}?horizon_hours=24',
      '$_mlUrl/forecast/${Uri.encodeComponent(userZone)}?horizon_hours=24',
      '$_mlUrl/forecast/${Uri.encodeComponent(city.toLowerCase())}?horizon_hours=24',
    ];
    
    for (final endpoint in endpoints) {
      try {
        final res = await http.get(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 12));
        
        if (res.statusCode == 200) {
          final data = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
          final forecast = (data['forecast'] as List?) ?? const [];
          setState(() {
            _forecastResult = {
              ...data,
              'forecasts': forecast.map((row) {
                final item = Map<String, dynamic>.from(row as Map);
                item['date'] = (item['ds']?.toString() ?? '').split('T').first;
                return item;
              }).toList(),
            };
            _forecastLoading = false;
          });
          return;
        }
      } catch (e) {
        print('[ML] Forecast endpoint failed: $e');
      }
    }
    
    // Compute mock forecast based on current month
    final now = DateTime.now();
    final isNEMonsoon = [10, 11, 12].contains(now.month);
    final isMonsoon = [6, 7, 8, 9].contains(now.month);
    
    final baseProb = isNEMonsoon ? 0.65 : isMonsoon ? 0.45 : 0.15;
    
    setState(() {
      _forecastResult = {
        'zone': userZone,
        'forecast': List.generate(3, (i) {
          final date = now.add(Duration(hours: (i + 1) * 6));
          final prob = baseProb + (i == 1 ? 0.1 : 0.0);
          return {
            'ds': date.toIso8601String(),
            'disruption_probability': prob,
            'trigger_type': prob > 0.15 ? 'heavy_rain' : 'normal',
          };
        }),
        'forecasts': List.generate(3, (i) {
          final date = now.add(Duration(hours: (i + 1) * 6));
          final prob = baseProb + (i == 1 ? 0.1 : 0.0);
          return {
            'date': date.toIso8601String().split('T').first,
            'disruption_probability': prob,
            'trigger_type': prob > 0.15 ? 'heavy_rain' : 'normal',
          };
        }),
        '_mock': true,
        '_source': 'seasonal_heuristic',
      };
      _forecastLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Row(children: [
          Container(width: 8, height: 8,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981))),
          const SizedBox(width: 8),
          const Text('ML Models — Live', style: TextStyle(color: Colors.white, fontSize: 16)),
          if (_loading) ...[
            const SizedBox(width: 10),
            const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(color: Color(0xFF10B981), strokeWidth: 2)),
          ],
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF10B981)),
            onPressed: _runAllModels,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF10B981),
        onRefresh: _runAllModels,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildModelCard(
                'M1 — ISS Score',
                'XGBoost — Income Stability',
                const Color(0xFF10B981),
                _issResult,
                isLoading: _issLoading,
                [
                  _resultRow('ISS Score', '${_issResult['iss_score'] ?? "—"} / 100'),
                  _resultRow('Risk Tier', _issResult['tier'] ?? '—'),
                  _resultRow('Plan Recommendation', _issResult['recommendation'] ?? '—'),
                ],
              ),
              const SizedBox(height: 12),
              _buildModelCard(
                'M2/M3 — Fraud Detection',
                'Isolation Forest — 50k samples trained',
                const Color(0xFFF59E0B),
                _fraudResult,
                [
                  _resultRow('Anomaly Score',
                    '${((_fraudResult['anomaly_score'] ?? 0.14) * 100).toStringAsFixed(1)} / 100'),
                  _resultRow('Decision',
                    (_fraudResult['is_anomalous'] == true) ? '🔴 FLAGGED' : '🟢 CLEAN'),
                  _resultRow('Top Signal',
                    (_fraudResult['top_features'] as List?)?.first ?? 'claim_latency'),
                ],
              ),
              const SizedBox(height: 12),
              _buildModelCard(
                'M7 — Prophet Forecast',
                'Facebook Prophet — 10 Chennai zones',
                const Color(0xFF3B82F6),
                _forecastResult,
                isLoading: _forecastLoading,
                [
                  if ((_forecastResult['forecasts'] as List?)?.isNotEmpty == true)
                    ...(_forecastResult['forecasts'] as List)
                      .take(3)
                      .map((f) => _resultRow(
                        f['date'],
                        '${((f['disruption_probability'] ?? 0) * 100).toStringAsFixed(0)}% — ${f['trigger_type']}',
                      ))
                      ,
                ],
              ),
              const SizedBox(height: 12),
              _buildModelCard(
                'Premium Calculator',
                'Zone + ISS adjusted pricing',
                const Color(0xFF8B5CF6),
                _premiumResult,
                [
                  _resultRow('Plan', 'Standard Shield'),
                  _resultRow('Base Premium', '₹${_premiumResult['base_premium'] ?? 49}'),
                  _resultRow('Zone Adjustment', '+₹${_premiumResult['zone_adjustment'] ?? 5}'),
                  _resultRow('Final Premium', '₹${_premiumResult['final_premium'] ?? 49}/week'),
                ],
              ),
              const SizedBox(height: 24),
              // Mock data indicator
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _anyMock()
                    ? '⚠️ Some results using fallback data — tap ↻ to retry live models'
                    : '✅ All results from live ML service',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _anyMock() =>
    _issResult['_mock'] == true ||
    _fraudResult['_mock'] == true ||
    _forecastResult['_mock'] == true;

  Widget _buildModelCard(
    String title,
    String subtitle,
    Color color,
    Map<String, dynamic> data,
    List<Widget> rows, {
    bool isLoading = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLoading ? Colors.orange :
                           (data['_mock'] == true ? Colors.orange : color),
                  ),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ]),
                const Spacer(),
                if (isLoading)
                  SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(color: color, strokeWidth: 2))
                else if (data['_mock'] == true)
                  const Text('MOCK', style: TextStyle(color: Colors.orange, fontSize: 9))
                else
                  Text('LIVE', style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Querying model...',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            Padding(
              padding: const EdgeInsets.all(14),
              child: rows.isEmpty
                ? const Text('No data returned',
                    style: TextStyle(color: Colors.grey, fontSize: 12))
                : Column(children: rows),
            ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value, style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
