import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/foundation.dart';

import 'shift_tracking_service.dart';
import 'storage_service.dart';

class BackgroundHeartbeatService {
  BackgroundHeartbeatService._();

  static bool _isStarted = false;

  static Future<void> initialize() async {
    if (kIsWeb || _isStarted) return;
    try {
      await BackgroundFetch.configure(
        BackgroundFetchConfig(
          minimumFetchInterval: 15,
          stopOnTerminate: false,
          startOnBoot: true,
          enableHeadless: true,
          requiredNetworkType: NetworkType.ANY,
        ),
        _onBackgroundFetch,
        _onBackgroundFetchTimeout,
      );
      await BackgroundFetch.start();
      _isStarted = true;
    } catch (e) {
      debugPrint('[BackgroundHeartbeatService] init failed: $e');
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !_isStarted) return;
    try {
      await BackgroundFetch.stop();
    } catch (e) {
      debugPrint('[BackgroundHeartbeatService] stop failed: $e');
    } finally {
      _isStarted = false;
    }
  }

  static Future<void> _onBackgroundFetch(String taskId) async {
    try {
      await StorageService.init();
      final active = await StorageService.instance.isShiftTrackingActive();
      if (active) {
        await ShiftTrackingService.instance.sendManualHeartbeat();
      }
    } catch (e) {
      debugPrint('[BackgroundHeartbeatService] fetch failed: $e');
    } finally {
      BackgroundFetch.finish(taskId);
    }
  }

  static void _onBackgroundFetchTimeout(String taskId) {
    BackgroundFetch.finish(taskId);
  }
}

