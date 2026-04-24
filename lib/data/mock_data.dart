import '../services/storage_service.dart';

/// Static trigger monitoring data used by TriggerStatusScreen.
/// Zone name is resolved from StorageService at runtime — no hardcoded values.
class MockData {
  static String get userZone =>
      StorageService.getString('userZone') ?? 'Your Zone';

  static const List<Map<String, dynamic>> liveStatus = [
    {
      'emoji': '🌧',
      'trigger': 'Heavy Rain',
      'reading': '12 mm/hr',
      'threshold': '64.5 mm/hr',
      'source': 'IMD Open Data',
      'status': 'NORMAL',
      'rate': '₹40/hr activated',
    },
    {
      'emoji': '🌡',
      'trigger': 'Extreme Heat',
      'reading': '41°C',
      'threshold': '43°C',
      'source': 'IMD Open Data',
      'status': 'ELEVATED',
      'rate': '₹40/hr activated',
    },
    {
      'emoji': '📱',
      'trigger': 'Platform Downtime',
      'reading': '99% uptime',
      'threshold': '< 90% uptime for 90 min',
      'source': 'Platform Status API',
      'status': 'NORMAL',
      'rate': '₹50/hr activated',
    },
    {
      'emoji': '💨',
      'trigger': 'Air Quality (AQI)',
      'reading': 'AQI 78',
      'threshold': 'AQI > 200',
      'source': 'AQICN',
      'status': 'NORMAL',
      'rate': '₹30/hr activated',
    },
    {
      'emoji': '📰',
      'trigger': 'Bandh / Strike',
      'reading': 'No alerts',
      'threshold': 'NLP confidence > 80%',
      'source': 'NewsAPI + NLP',
      'status': 'NORMAL',
      'rate': '₹49/wk activated',
    },
  ];
}
