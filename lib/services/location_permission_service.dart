import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationPermissionService {
  /// Requests foreground + background location permissions.
  /// Returns true if at least foreground location is granted.
  static Future<bool> requestAllLocationPermissions() async {
    // Step 1: Check & request foreground (precise) location
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }

    // Step 2: Request background location (separate prompt on Android 10+)
    // This triggers "Allow all the time" vs "Only while using the app"
    await Permission.locationAlways.request();

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  static Future<bool> hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  static Future<bool> hasBackgroundPermission() async {
    return await Permission.locationAlways.isGranted;
  }

  static Future<Position?> getCurrentPosition() async {
    if (!await hasLocationPermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Background-aware location stream with a foreground notification.
  static Stream<Position> getLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50, // update every 50 metres
        intervalDuration: const Duration(minutes: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText:
              'Hustlr is monitoring your zone for disruption payouts',
          notificationTitle: 'Zone Protection Active',
          enableWakeLock: true,
          notificationIcon: AndroidResource(
            name: 'ic_notification',
            defType: 'drawable',
          ),
        ),
      ),
    );
  }
}
