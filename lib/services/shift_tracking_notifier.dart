import 'package:flutter/foundation.dart';

class ShiftTrackingNotifier extends ChangeNotifier {
  static final instance = ShiftTrackingNotifier._();
  ShiftTrackingNotifier._();

  bool isActive = false;
  bool hasTrigger = false;
  double lat = 0;
  double lng = 0;
  double accuracy = 0;
  DateTime? lastGpsUpdate;

  void notify(double latitude, double longitude, double acc) {
    lat = latitude;
    lng = longitude;
    accuracy = acc;
    isActive = true;
    lastGpsUpdate = DateTime.now();
    notifyListeners();
  }

  void notifyTrigger(String triggerType) {
    hasTrigger = true;
    notifyListeners();
  }

  void clearTrigger() {
    hasTrigger = false;
    notifyListeners();
  }

  void notifyLocationDisabled() {
    isActive = false;
    notifyListeners();
  }
}
