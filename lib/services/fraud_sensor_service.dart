import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Fraud sensor collector used by both live checks and hackathon/demo flows.
///
/// Important:
/// - `mockFraudSpoofing` is intentionally used to simulate spoofed GPS behavior.
/// - In spoof mode, payload fields are forced to deterministic values for testing.
/// - Dashboard debug controls and claim/risk screens depend on this behavior.
/// - Do not "clean up" spoof mode unless demo/testing flows are also updated.
class FraudSensorService {
  /// Demo toggle: when enabled, returns a fixed spoof-like payload.
  static bool mockFraudSpoofing = false;

  /// Captures a sensor payload including GPS coordinates, GPS jitter (std div), 
  /// and barometric pressure if available. Also gathers basic device spoofing heuristics.
  static Future<Map<String, dynamic>> collectPayload() async {
    final payload = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'platform': kIsWeb ? 'web' : 'native',
    };

    if (mockFraudSpoofing) {
      payload['latitude'] = 13.0827; // Mock fixed location
      payload['longitude'] = 80.2707;
      payload['altitude'] = 0.0;
      payload['accuracy'] = 1.0;
      payload['is_mocked'] = true;
      // Intentional demo signal: backend logic treats 0.0 jitter as high-risk.
      payload['gps_jitter'] = 0.0;
      payload['samples'] = 4;
      return payload;
    }

    if (kIsWeb) {
      // Web can't really access Barometer and Jitter is restricted.
      return payload;
    }

    try {
      // Barometer removed due to plugin compilation issues

      // 2. Location & Jitter (std dev)
      final locAllowed = await _checkLocationPermission();
      if (locAllowed) {
        final List<Position> positions = [];
        
        // Grab rapid consecutive locations over a 2-second window to detect spoofed stationary APIs
        for (int i = 0; i < 4; i++) {
          try {
            final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 1),
            );
            positions.add(pos);
            await Future.delayed(const Duration(milliseconds: 300));
          } catch (_) {
            break;
          }
        }

        if (positions.isNotEmpty) {
          final p0 = positions.first;
          payload['latitude'] = p0.latitude;
          payload['longitude'] = p0.longitude;
          payload['altitude'] = p0.altitude;
          payload['accuracy'] = p0.accuracy;
          payload['is_mocked'] = p0.isMocked;

          // Calculate simple Jitter (Standard Deviation of Coordinates)
          if (positions.length > 1) {
            final avgLat = positions.map((p) => p.latitude).reduce((a, b) => a + b) / positions.length;
            final avgLon = positions.map((p) => p.longitude).reduce((a, b) => a + b) / positions.length;
            
            final sqDiffLat = positions.map((p) => (p.latitude - avgLat) * (p.latitude - avgLat)).reduce((a, b) => a + b);
            final sqDiffLon = positions.map((p) => (p.longitude - avgLon) * (p.longitude - avgLon)).reduce((a, b) => a + b);
            
            final varianceLat = sqDiffLat / positions.length;
            final varianceLon = sqDiffLon / positions.length;
            
            payload['gps_jitter'] = (varianceLat + varianceLon);
            payload['samples'] = positions.length;
          } else {
             payload['gps_jitter'] = 0.0;
          }
        }
      }
    } catch (e) {
      debugPrint('Fraud Sensor Error: $e');
    }

    return payload;
  }

  static Future<bool> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    } 

    return true;
  }
}
