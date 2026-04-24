import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class MlTesterScreen extends StatefulWidget {
  const MlTesterScreen({super.key});

  @override
  State<MlTesterScreen> createState() => _MlTesterScreenState();
}

class _MlTesterScreenState extends State<MlTesterScreen> {
  // Uses the Node backend to proxy the request to the ML service
  String _baseUrl = '${ApiService.baseUrl}/ml';
  
  String _responseLog = '';
  bool _isLoading = false;

  Future<void> _testFraud() async {
    setState(() { _isLoading = true; _responseLog = 'Testing Fraud...'; });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/fraud'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "worker_id": "sim_worker_123",
          "zone_id": "Adyar Dark Store Zone",
          "claim_timestamp": DateTime.now().toIso8601String(),
          "feature_vector": {
            "zone_match": 0.85,
            "gps_jitter": 0.10,
            "accelerometer_match": 0.90,
            "wifi_home_ssid": false,
            "days_since_onboarding": 30
          }
        }),
      ).timeout(const Duration(seconds: 70));
      setState(() { _responseLog = 'Status: ${res.statusCode}\\nResponse:\\n${const JsonEncoder.withIndent('  ').convert(jsonDecode(res.body))}'; });
    } catch (e) {
      setState(() { _responseLog = 'Error: $e'; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _testISS() async {
    setState(() { _isLoading = true; _responseLog = 'Testing ISS Engine...'; });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/iss'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "zone_flood_risk": 0.60,
          "avg_daily_income": 600.0,
          "disruption_freq_12mo": 8,
          "platform_tenure_weeks": 4,
          "city": "Chennai"
        }),
      ).timeout(const Duration(seconds: 70));
      setState(() { _responseLog = 'Status: ${res.statusCode}\\nResponse:\\n${const JsonEncoder.withIndent('  ').convert(jsonDecode(res.body))}'; });
    } catch (e) {
      setState(() { _responseLog = 'Error: $e'; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _testPremium() async {
    setState(() { _isLoading = true; _responseLog = 'Testing Premium Pricing...'; });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/premium'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "plan_tier": "standard",
          "zone": "Adyar Dark Store Zone",
          "iss_score": 62,
          "previous_premium": 0.0
        }),
      ).timeout(const Duration(seconds: 70));
      setState(() { _responseLog = 'Status: ${res.statusCode}\\nResponse:\\n${const JsonEncoder.withIndent('  ').convert(jsonDecode(res.body))}'; });
    } catch (e) {
      setState(() { _responseLog = 'Error: $e'; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1B5E20);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ML Data Tester (Demo)', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Note: This screen now proxies requests through the Node.js backend to the Phase 3 ML endpoints.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.blueAccent)),
            const SizedBox(height: 12),
            TextField(
              onChanged: (val) => _baseUrl = val,
              decoration: const InputDecoration(labelText: 'Backend URL / IP', hintText: 'http://127.0.0.1:3000/ml', border: OutlineInputBorder()),
              controller: TextEditingController(text: _baseUrl),
            ),
            const SizedBox(height: 16),
            
            const Text('🛡️ Isolation Forest Fraud Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white),
              onPressed: _isLoading ? null : _testFraud,
              child: const Text('Test Fraud Model'),
            ),
            const Divider(height: 32),

            const Text('📊 ISS Score Engine (XGBoost)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white),
              onPressed: _isLoading ? null : _testISS,
              child: const Text('Test ISS Pipeline'),
            ),
            const Divider(height: 32),

            const Text('💸 Dynamic Premium Pricing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white),
              onPressed: _isLoading ? null : _testPremium,
              child: const Text('Test Actuarial Pricing'),
            ),
            const Divider(height: 32),

            const Text('Response Output', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isDark ? Colors.black : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
              child: SelectableText(_responseLog, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
