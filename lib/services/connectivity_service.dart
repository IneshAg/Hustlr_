import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'app_events.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService instance = ConnectivityService._internal();
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  // True if the actual backend is reachable
  bool _isReachable = true;
  bool get isReachable => _isOnline && _isReachable;

  Timer? _reachabilityTimer;

  Future<void> initialize() async {
    _subscription = _connectivity.onConnectivityChanged.listen(_handleConnectivityChange);
    // Initial check
    final result = await _connectivity.checkConnectivity();
    await _handleConnectivityChange(result);
  }

  Future<void> _handleConnectivityChange(List<ConnectivityResult> results) async {
    final hasHardwareConnection = !results.contains(ConnectivityResult.none);
    final wasOnline = _isOnline;
    
    if (hasHardwareConnection || true) { // Bypass strict hardware check to avoid emulator bugs
      _isOnline = true;
      // Start pinging backend if we weren't already
      _startReachabilityCheck();
    } else {
      _isOnline = false;
      _isReachable = false;
      _stopReachabilityCheck();
      notifyListeners();
    }

    if (!wasOnline && _isOnline) {
      // Hardware connection restored, verify API
      await _checkReachability();
    }
  }

  void _startReachabilityCheck() {
    _stopReachabilityCheck();
    // Ping immediately, then every 30 seconds
    _checkReachability();
    _reachabilityTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkReachability();
    });
  }

  void _stopReachabilityCheck() {
    _reachabilityTimer?.cancel();
    _reachabilityTimer = null;
  }

  Future<bool> _checkReachability() async {
    // ALWAYS try pinging the backend, emulator hardware checks can be buggy
    final wasReachable = _isReachable;
    
    try {
      // Probe the public health endpoint; auth-protected admin health checks can
      // incorrectly report unreachable for normal users.
      final url = Uri.parse('${ApiService.baseUrl}/health');
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      _isReachable = response.statusCode == 200 || response.statusCode == 404; // Even 404 means server responded
    } catch (e) {
      debugPrint('[ConnectivityService] Ping failed: $e');
      _isReachable = false;
    }

    if (wasReachable != _isReachable) {
      if (!wasReachable && _isReachable) {
        // App just regained actual internet connection to our backend
        AppEvents.instance.connectivityRestored();
      }
      notifyListeners();
    }
    
    return _isReachable;
  }

  /// Forces an immediate reachability check. Useful before submitting claims.
  Future<bool> checkNow() async {
    _isOnline = true; // Assume online to allow ping to happen
    return await _checkReachability();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stopReachabilityCheck();
    super.dispose();
  }
}
