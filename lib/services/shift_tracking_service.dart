import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_service.dart';
import 'notification_service.dart';
import 'shift_tracking_notifier.dart';
import 'storage_service.dart';
import 'location_service.dart';

enum ShiftStatus { offline, active, paused }

class FrsSignal {
  final String flag;
  final int score;
  final DateTime timestamp;

  FrsSignal({
    required this.flag,
    required this.score,
    required this.timestamp,
  });
}

class ShiftTrackingService extends ChangeNotifier {
  static final ShiftTrackingService instance = ShiftTrackingService._internal();
  ShiftTrackingService._internal();

  ShiftStatus _status = ShiftStatus.offline;
  double _lastAccuracy = 0.0;
  DateTime? _lastHeartbeatAt;
  final List<FrsSignal> _frsSignals = [];
  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;
  Future<void>? _transitionFuture;
  String _activeZone = 'Unknown Zone';

  ShiftStatus get status => _status;
  double get lastAccuracy => _lastAccuracy;
  DateTime? get lastHeartbeatAt => _lastHeartbeatAt;
  List<FrsSignal> get frsSignals => List.unmodifiable(_frsSignals);

  String get gpsStateLabel {
    if (_status == ShiftStatus.paused) return 'paused';
    if (_status == ShiftStatus.offline) return 'offline';
    if (_lastAccuracy > 50) return 'weak';
    return 'active';
  }

  Future<void> _runSerialized(Future<void> Function() action) async {
    while (_transitionFuture != null) {
      try {
        await _transitionFuture;
      } catch (_) {}
    }
    final future = action();
    _transitionFuture = future;
    try {
      await future;
    } finally {
      if (identical(_transitionFuture, future)) {
        _transitionFuture = null;
      }
    }
  }

  Future<bool> _ensurePermissions() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _status = ShiftStatus.paused;
      notifyListeners();
      ShiftTrackingNotifier.instance.notifyLocationDisabled();
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    // For background location, we need 'Always'
    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      _status = ShiftStatus.paused;
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> startShift(String zone) async {
    await _runSerialized(() async {
      final ok = await _ensurePermissions();
      if (!ok) return;

      _activeZone = zone;
      await StorageService.instance.saveShiftZone(zone);
      await StorageService.instance.setShiftTrackingActive(true);
      await _positionSubscription?.cancel();
      _heartbeatTimer?.cancel();

      await LocationService.instance.startTracking(zone);

      _status = ShiftStatus.active;
      notifyListeners();

      try {
        final initial = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        await _handlePosition(initial, isHeartbeat: false);
      } catch (e) {
        if (kDebugMode) {
          print('[ShiftTrackingService] Initial GPS fix failed: $e');
        }
      }

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: "Shift Protection Active",
            notificationText: "Hustlr is protecting your earnings in the background.",
            enableWakeLock: true,
          ),
        ),
      ).listen(
        (position) => _handlePosition(position, isHeartbeat: false),
        onError: (Object error) {
          if (kDebugMode) {
            print('[ShiftTrackingService] Position stream error: $error');
          }
          if (_status == ShiftStatus.active) {
            _status = ShiftStatus.paused;
            notifyListeners();
            NotificationService.instance.addShiftPaused();
          }
        },
      );

      _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
        if (_status != ShiftStatus.active) return;
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 20),
          );
          await _handlePosition(position, isHeartbeat: true);
        } catch (_) {}
      });
    });
  }

  Future<void> stopShift() async {
    await _runSerialized(() async {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      await StorageService.instance.setShiftTrackingActive(false);
      
      await LocationService.instance.stopTracking();

      _status = ShiftStatus.offline;
      _frsSignals.clear();
      notifyListeners();
    });
  }

  void resumeShift() async {
    if (_status == ShiftStatus.paused) {
      await startShift(_activeZone);
    }
  }

  Future<void> restoreActiveShiftOnLaunch() async {
    final isOffDuty = await StorageService.instance.isOffDuty();
    if (isOffDuty) return;

    final wasActive = await StorageService.instance.isShiftTrackingActive();
    if (!wasActive || _status == ShiftStatus.active) return;

    final savedZone = await StorageService.instance.getShiftZone();
    final zone = (savedZone == null || savedZone.isEmpty) ? 'Local Zone' : savedZone;
    await startShift(zone);
  }

  Future<void> _handlePosition(Position position, {required bool isHeartbeat}) async {
    final lat = position.latitude;
    final lng = position.longitude;
    final accuracy = position.accuracy;

    _lastAccuracy = accuracy;
    _lastHeartbeatAt = DateTime.now();
    await StorageService.instance.setLastLat(lat);
    await StorageService.instance.setLastLng(lng);

    if (_status == ShiftStatus.paused) {
      _status = ShiftStatus.active;
      NotificationService.instance.addShiftResumed();
    }

    final isMock = position.isMocked;
    if (isMock) {
      _addFrsSignal('mock_location_detected', 100);
      NotificationService.instance.addFraudAlert();
      await stopShift();
      return;
    }

    final isLowConfidence = accuracy > 50;
    final speed = position.speed;
    if (speed > 25.0) {
      _addFrsSignal('impossible_speed_detected', 15);
    }

    notifyListeners();
    ShiftTrackingNotifier.instance.notify(lat, lng, accuracy);
    await _sendHeartbeat(position, isMock, isLowConfidence, isHeartbeat: isHeartbeat);
  }

  Future<void> _sendHeartbeat(
    Position pos,
    bool isMock,
    bool lowConf, {
    required bool isHeartbeat,
  }) async {
    try {
      final userId = await StorageService.instance.getUserId();
      if (userId == null || userId.isEmpty) return;
      
      // Stop 404 spam: Only send heartbeats for real backend users (UUIDs), not local phone number logins
      final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(userId);
      if (!isUuid) return;

      await ApiService.instance.postShiftHeartbeat(
        workerId: userId,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        timestamp: pos.timestamp.toIso8601String(),
        isMockLocation: isMock,
        activityType: isHeartbeat ? 'heartbeat' : 'in_vehicle',
        batteryLevel: null,
        isLowConfidence: lowConf,
      );
    } catch (_) {}
  }

  Future<void> sendManualHeartbeat({bool isHeartbeat = true}) async {
    final ok = await _ensurePermissions();
    if (!ok) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      await _handlePosition(position, isHeartbeat: isHeartbeat);
    } catch (_) {}
  }

  void _addFrsSignal(String flag, int score) {
    _frsSignals.add(FrsSignal(flag: flag, score: score, timestamp: DateTime.now()));
    if (kDebugMode) {
      debugPrint('[FRS] +$score - $flag');
    }
  }
}
