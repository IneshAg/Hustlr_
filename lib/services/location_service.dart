import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'notification_service.dart';

class StatusEvent {
  final String message;
  final DateTime timestamp;
  final bool isError;

  StatusEvent(this.message, {DateTime? timestamp, this.isError = false}) 
    : timestamp = timestamp ?? DateTime.now();
}

class LocationService extends ChangeNotifier {
  static final LocationService instance = LocationService._internal();
  LocationService._internal();

  final List<Position> _shiftPings = [];
  double _currentDepthScore = 0.0;
  double _currentLat = 0.0;
  double _currentLon = 0.0;
  bool _isTracking = false;
  String _currentZone = 'Unknown';
  double _traveledDistance = 0.0;
  StreamSubscription<Position>? _positionStreamSubscription;

  final StreamController<StatusEvent> _eventController = StreamController<StatusEvent>.broadcast();
  Stream<StatusEvent> get eventLog => _eventController.stream;

  // Mock overrides
  double? _mockDepthScore;
  double? _mockLat;
  double? _mockLon;
  String? _mockZone;

  double get depthScore => _mockDepthScore ?? _currentDepthScore;
  double get currentLat => _mockLat ?? _currentLat;
  double get currentLon => _mockLon ?? _currentLon;
  bool get isTracking => _isTracking;
  String get currentZone => _mockZone ?? _currentZone;
  double get traveledDistance => _traveledDistance;

  void addEvent(String message, {bool isError = false}) {
    _eventController.add(StatusEvent(message, isError: isError));
  }

  /// Push a one-shot GPS fix into the service without starting full tracking.
  /// Used by the dashboard to show location immediately on mount.
  void updateFromGps(double lat, double lon) {
    _currentLat = lat;
    _currentLon = lon;
    notifyListeners();
  }

  static const Map<String, Map<String, double>> ZONE_CENTROIDS = {
    'Adyar Dark Store Zone':              {'lat': 13.0067, 'lon': 80.2206},
    'Anna Nagar Dark Store Zone':         {'lat': 13.0850, 'lon': 80.2101},
    'T Nagar Dark Store Zone':            {'lat': 13.0418, 'lon': 80.2341},
    'Velachery Dark Store Zone':          {'lat': 12.9815, 'lon': 80.2180},
    'OMR Dark Store Zone':                {'lat': 12.9165, 'lon': 80.2275},
    'Tambaram Dark Store Zone':           {'lat': 12.9249, 'lon': 80.1000},
    'Porur Dark Store Zone':              {'lat': 13.0358, 'lon': 80.1566},
    'Sholinganallur Dark Store Zone':     {'lat': 12.9010, 'lon': 80.2279},
    'Mylapore Dark Store Zone':           {'lat': 13.0368, 'lon': 80.2676},
    'Perambur Dark Store Zone':           {'lat': 13.1080, 'lon': 80.2480},
    'Kattankulathur Dark Store Zone':     {'lat': 12.8185, 'lon': 80.0419}, // SRM Uni corridor
    'Koramangala Dark Store Zone':        {'lat': 12.9352, 'lon': 77.6245},
    'HSR Layout Dark Store Zone':         {'lat': 12.9081, 'lon': 77.6476},
    'Indiranagar Dark Store Zone':        {'lat': 12.9784, 'lon': 77.6408},
    'Andheri Dark Store Zone':            {'lat': 19.1136, 'lon': 72.8697},
    'Bandra Dark Store Zone':             {'lat': 19.0596, 'lon': 72.8295},
  };

  static const double ZONE_OUTER_RADIUS = 3.0;
  static const double ZONE_MIDDLE_RADIUS = 2.0;
  static const double ZONE_CORE_RADIUS = 1.0;

  Future<void> initialize() async {
    // No mandatory auto-start here.
  }

  Future<bool> _requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // For background location on Android, we need 'Always' permission
    if (permission == LocationPermission.whileInUse) {
      // Prompt for 'Always' once if possible
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  Future<void> startTracking(String zone) async {
    final hasPermission = await _requestPermissions();
    if (!hasPermission) return;

    _currentZone = zone;
    _shiftPings.clear();
    _currentDepthScore = 0.0;
    _traveledDistance = 0.0;
    _isTracking = true;
    addEvent('Location protection online');
    notifyListeners();

    // Fetch initial location immediately so UI doesn't show 0.0000
    try {
      Position initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _currentLat = initialPos.latitude;
      _currentLon = initialPos.longitude;
      _shiftPings.add(initialPos);
      // Auto-detect zone from real GPS (overrides the short onboarding name)
      final detectedZone = _findNearestZone(initialPos.latitude, initialPos.longitude);
      if (detectedZone != 'Outside Service Area' && detectedZone != 'Unknown Zone') {
        _currentZone = detectedZone;
      }
      _recalculateDepthScore();
      notifyListeners();
    } catch (_) {}

    _listenToPositions();
  }

  Future<void> stopTracking() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _isTracking = false;
    _mockDepthScore = null;
    _mockLat = null;
    _mockLon = null;
    _mockZone = null;
    addEvent('Location protection offline');
    notifyListeners();
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    final dist = Geolocator.distanceBetween(
      lat1, lon1, lat2, lon2
    );
    return dist / 1000.0; // km
  }

  String _findNearestZone(double lat, double lon) {
    String nearest = 'Unknown Zone';
    double minDict = 99999.0;
    
    ZONE_CENTROIDS.forEach((name, coords) {
      final d = _calculateDistance(lat, lon, coords['lat']!, coords['lon']!);
      if (d < minDict) {
        minDict = d;
        nearest = name;
      }
    });

    // If we are way outside any dark store (e.g. > 50km), keep as Unknown
    if (minDict > 50.0) return 'Outside Service Area';
    return nearest;
  }

  void _listenToPositions() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 20, // Hardware filter: only emit after 20m real movement
      ),
    ).listen((position) {
      if (!_isTracking) return;

      // Accuracy guard: ignore noisy fixes (GPS jitter on both web and phone)
      // A reading worse than 30m accuracy is pure noise when stationary.
      if (position.accuracy > 30.0) return;

      if (_shiftPings.isNotEmpty) {
        final lastPing = _shiftPings.last;
        final distanceDelta = Geolocator.distanceBetween(
          lastPing.latitude,
          lastPing.longitude,
          position.latitude,
          position.longitude,
        );
        final timeDeltaSec = position.timestamp.difference(lastPing.timestamp).inSeconds.abs();
        
        // Fraud Check: If distance > 100 meters AND speed > 20 m/s (72 km/h)
        if (timeDeltaSec > 0 && distanceDelta > 100) {
          final speed = distanceDelta / timeDeltaSec;
          if (speed > 20.0) {
            NotificationService.instance.addFraudAlert();
            stopTracking();
            return;
          }
        }

        // Software gate: only accumulate distance if movement >= 20m
        // This prevents GPS drift noise from inflating the protected distance.
        if (distanceDelta >= 20.0) {
          _traveledDistance += (distanceDelta / 1000.0);
        }
      }

      _currentLat = position.latitude;
      _currentLon = position.longitude;
      _shiftPings.add(position);

      // Auto-detect zone from live GPS so a short zone name from onboarding
      // still resolves to the correct dark-store centroid.
      final detectedZone = _findNearestZone(position.latitude, position.longitude);
      if (detectedZone != 'Outside Service Area' && detectedZone != 'Unknown Zone') {
        _currentZone = detectedZone;
      }

      final cutoff = DateTime.now().subtract(const Duration(hours: 8));
      _shiftPings.removeWhere((p) => p.timestamp.isBefore(cutoff));

      _recalculateDepthScore();
      final centroid = _getCentroid(_currentZone);
      if (centroid != null) {
        final hubDist = _haversineKm(
          position.latitude, position.longitude,
          centroid['lat']!, centroid['lon']!,
        );
        addEvent('Zone: $_currentZone · ${hubDist.toStringAsFixed(2)} km to hub');
      }
      
      notifyListeners();
    });
  }



  void forceMockLocation(String zone, double lat, double lon, {double? depthScore}) {
    _mockZone = zone;
    _mockLat = lat;
    _mockLon = lon;
    _mockDepthScore = depthScore;
    notifyListeners();
  }

  void clearMockLocation() {
    _mockZone = null;
    _mockLat = null;
    _mockLon = null;
    _mockDepthScore = null;
    notifyListeners();
  }

  void _recalculateDepthScore() {
    if (_shiftPings.isEmpty || _currentZone == 'Unknown') return;
    final centroid = _getCentroid(_currentZone);
    if (centroid == null) return;

    double totalScore = 0.0;
    for (final ping in _shiftPings) {
      final distKm = _haversineKm(
        ping.latitude, ping.longitude,
        centroid['lat']!, centroid['lon']!,
      );

      double pingScore;
      if (distKm <= ZONE_CORE_RADIUS) {
        pingScore = 0.8 + (1.0 - distKm / ZONE_CORE_RADIUS) * 
        .2;
      } else if (distKm <= ZONE_MIDDLE_RADIUS) {
        pingScore = 0.4 + (1.0 - (distKm - ZONE_CORE_RADIUS) /
        
            (ZONE_MIDDLE_RADIUS - ZONE_CORE_RADIUS)) * 0.4;
      } else if (distKm <= ZONE_OUTER_RADIUS) {
        pingScore = (1.0 - (distKm - ZONE_MIDDLE_RADIUS) /
            (ZONE_OUTER_RADIUS - ZONE_MIDDLE_RADIUS)) * 0.4;
      } else {
        pingScore = 0.0;
      }
      totalScore += pingScore;
    }

    _currentDepthScore = totalScore / _shiftPings.length;
    _currentDepthScore = _currentDepthScore.clamp(0.0, 1.0);
  }

  double getDepthMultiplier() {
    if (_currentDepthScore <= 0.20) return 0.0;
    if (_currentDepthScore <= 0.40) return 0.3;
    if (_currentDepthScore <= 0.60) return 0.6;
    if (_currentDepthScore <= 0.80) return 0.85;
    return 1.0;
  }

  double calculateFinalPayout(double grossPayout) {
    return (grossPayout * getDepthMultiplier()).roundToDouble();
  }

  double getGpsJitterVariance() {
    if (_shiftPings.length < 3) return 0.0;
    final recent = _shiftPings.take(10).toList();
    final lats = recent.map((p) => p.latitude).toList();
    final mean = lats.reduce((a, b) => a + b) / lats.length;
    final variance = lats
        .map((l) => (l - mean) * (l - mean))
        .reduce((a, b) => a + b) / lats.length;
    return variance;
  }

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * pi / 180;

  Map<String, dynamic> getClaimSensorData() {
    return {
      'gps_lat':           _currentLat,
      'gps_lon':           _currentLon,
      'gps_jitter':        getGpsJitterVariance(),
      'depth_score':       _currentDepthScore,
      'depth_multiplier':  getDepthMultiplier(),
      'ping_count':        _shiftPings.length,
      'zone':              _currentZone,
      'is_tracking':       _isTracking,
    };
  }

  /// Fuzzy lookup: handles both exact keys ("Kattankulathur Dark Store Zone")
  /// and short names ("Kattankulathur") stored in onboarding/worker profile.
  Map<String, double>? _getCentroid(String zone) {
    if (ZONE_CENTROIDS.containsKey(zone)) return ZONE_CENTROIDS[zone];
    // Try appending standard suffix
    final suffixed = '$zone Dark Store Zone';
    if (ZONE_CENTROIDS.containsKey(suffixed)) return ZONE_CENTROIDS[suffixed];
    // Partial match (case-insensitive)
    final lower = zone.toLowerCase();
    for (final entry in ZONE_CENTROIDS.entries) {
      final key = entry.key.toLowerCase().replaceAll(' dark store zone', '');
      if (key.contains(lower) || lower.contains(key)) return entry.value;
    }
    return null;
  }
}
