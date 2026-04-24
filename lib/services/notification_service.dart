import '../models/notification_model.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'api_service.dart';
import 'storage_service.dart';

typedef NotificationTapCallback = Future<void> Function(Map<String, dynamic> payload);

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static int _localNotificationId = 0;
  static bool _localReady = false;
  static NotificationTapCallback? _onNotificationTap;
  static String? _lastSyncedToken;

  static const AndroidNotificationChannel _defaultChannel =
      AndroidNotificationChannel(
    'hustlr_default_channel',
    'Hustlr Alerts',
    description: 'Important payment and protection alerts from Hustlr',
    importance: Importance.max,
  );

  /// Low-priority silent channel for the persistent foreground service icon.
  /// This keeps the icon in the status bar without making noise in the drawer.
  static const AndroidNotificationChannel _shiftServiceChannel =
      AndroidNotificationChannel(
    'hustlr_shift_service',
    'Shift Protection',
    description: 'Indicates your shift protection is running in the background.',
    importance: Importance.min,
    showBadge: false,
  );

  /// Set callback for handling notification taps
  static void setNotificationTapCallback(NotificationTapCallback callback) {
    _onNotificationTap = callback;
  }

  static Future<void> initialize() async {
    if (!kIsWeb) {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings =
          InitializationSettings(android: androidInit, iOS: iosInit);
      
      await _localNotifications.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) async {
          // Handle tap on local notification
          if (response.payload != null && response.payload!.isNotEmpty) {
            try {
              final payload = jsonDecode(response.payload!);
              await _onNotificationTap?.call(payload);
            } catch (e) {
              print('Error handling notification tap: $e');
            }
          }
        },
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_defaultChannel);
      await androidPlugin?.createNotificationChannel(_shiftServiceChannel);
      await androidPlugin?.requestNotificationsPermission();

      final iosPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

      _localReady = true;
    }

    // Firebase calls can crash if Firebase is not initialized, especially on web.
    try {
      if (kIsWeb) return; // Skip push notifications on web for demo purposes

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Foreground messages - display in notification bar
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ?? 'Hustlr Update';
        final body = message.notification?.body ?? 'You have a new activity update.';
        
        // Include data payload for navigation
        _showLocalNotification(
          title: title,
          body: body,
          payload: message.data,
        );
      });

      // When notification is clicked (app in background or terminated)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('Notification opened app: ${message.data}');
        _onNotificationTap?.call(message.data);
      });

      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        await syncDevicePushToken(tokenOverride: token);
      });
      await syncDevicePushToken();
    } catch (e) {
      print('Firebase messaging init skipped: $e');
    }
  }

  static Future<bool> syncDevicePushToken({String? tokenOverride}) async {
    try {
      if (kIsWeb) return false;
      final userId = StorageService.userId;
      if (userId.isEmpty) return false;

      final token = (tokenOverride?.trim().isNotEmpty == true)
          ? tokenOverride!.trim()
          : (await FirebaseMessaging.instance.getToken() ?? '').trim();
      if (token.isEmpty) return false;
      if (_lastSyncedToken == token) return true;

      final ok = await ApiService.instance.registerFcmToken(
        userId: userId,
        token: token,
      );
      if (ok) _lastSyncedToken = token;
      return ok;
    } catch (e) {
      print('FCM token sync failed: $e');
      return false;
    }
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    if (kIsWeb || !_localReady) return;
    
    final payloadJson = payload != null ? jsonEncode(payload) : '';
    
    const androidDetails = AndroidNotificationDetails(
      'hustlr_default_channel',
      'Hustlr Alerts',
      channelDescription:
          'Important payment and protection alerts from Hustlr',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true, // Helps with heads-up
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _localNotifications.show(
      id: _localNotificationId++,
      title: title,
      body: body,
      payload: payloadJson,
      notificationDetails: details,
    );
  }

  final List<HustlrNotification> _notifications = [];

  List<HustlrNotification> get all =>
      _notifications..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void markAllRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
  }

  void markRead(String id) {
    _notifications.firstWhere((n) => n.id == id).isRead = true;
  }

  void addRainAlert(String zone) {
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'rain_alert',
      title: 'Heavy rain expected in $zone',
      body: 'Your coverage auto-activates. No action needed.',
      color: 'blue',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }

  void addClaimApproved(int tranche1Amount) {
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'claim_approved',
      title: 'Claim approved — ₹$tranche1Amount credited',
      body: '70% of your payout has been added to your wallet.',
      color: 'green',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }

  void addClaimCreated({required String triggerType, required int amount}) {
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'claim_created',
      title: '$triggerType — Claim Filed',
      body: 'Your claim has been created. Awaiting verification.',
      color: 'blue',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }

  void addWalletCredited({required int amount}) {
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'wallet_credited',
      title: '₹$amount credited to wallet',
      body: 'Payout has been added to your wallet balance.',
      color: 'green',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }

  void addDisruptionAlert({required String triggerType, required String zone}) {
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'disruption_alert',
      title: '$triggerType in $zone',
      body: 'Disruption detected in your zone. Coverage may apply.',
      color: 'amber',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }

  void addPremiumDeducted(int amount, {String? planName}) {
    final normalizedPlan = planName?.trim();
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'premium_deducted',
      title: 'Weekly premium deducted — ₹$amount',
      body: (normalizedPlan != null && normalizedPlan.isNotEmpty)
          ? 'Plan: $normalizedPlan. You are covered for this week. Stay safe.'
          : 'You are covered for this week. Stay safe.',
      color: 'green',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }

  // Only call this when user has NO active policy
  void addMissedPayout(int amount) {
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'missed_payout',
      title: 'You missed ₹$amount today',
      body: 'If you were covered, this would be in your wallet right now.',
      color: 'amber',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }

  void addShiftPaused() {
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'shift_paused',
      title: 'GPS signal lost — coverage paused',
      body: 'Re-enable location to resume your shift protection. Claims during this gap cannot be verified.',
      color: 'red',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }

  void addShiftResumed() {
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'shift_resumed',
      title: 'Location restored — you\'re covered again',
      body: 'Your shift protection has resumed. The gap has been logged.',
      color: 'green',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }

  void addFraudAlert() {
    final item = HustlrNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: 'fraud_alert',
      title: 'Suspicious Location Activity',
      body: 'Your coverage is temporarily suspended due to impossible GPS jumping (Velocity Fraud).',
      color: 'red',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, item);
    _showLocalNotification(title: item.title, body: item.body);
  }
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    final title = message.notification?.title ?? message.data['title'] ?? 'Hustlr Update';
    final body = message.notification?.body ?? message.data['body'] ?? 'New activity detected.';
    
    // We need to re-initialize for background isolate if not ready
    if (!_localReady) {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: androidInit);
      await _localNotifications.initialize(settings: settings);
      _localReady = true;
    }

    await _showLocalNotification(
      title: title,
      body: body,
      payload: message.data,
    );
  }
}
