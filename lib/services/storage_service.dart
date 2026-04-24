import 'package:shared_preferences/shared_preferences.dart';
import '../models/pending_claim_queue_item.dart';
/// Local persistence for auth, onboarding, and profile fields.
/// Keeps static accessors (used by [MockDataService], [AuthService]) in sync with instance helpers.
class StorageService {
  static final StorageService instance = StorageService._internal();
  StorageService._internal();

  static late SharedPreferences _prefs;
  static bool _isInitialized = false;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  static const _keyIsLoggedIn = 'isLoggedIn';
  static const _keyIsOnboardedLegacy = 'isOnboarded';
  static const _keyHasSeenCarousel = 'hasSeenCarousel';
  static const _keyPhone = 'phone';
  static const _keyUserId = 'userId';
  static const _keyPolicyId = 'policyId';
  static const _keyUserZone = 'userZone';
  static const _keyOnboardingComplete = 'onboardingComplete';
  static const _keyShiftActive = 'shiftActive';
  static const _keyShiftZone = 'shiftZone';
    static const _keyOffDutyMode = 'offDutyMode';
  static const _keyUpiId = 'upiId';
  static const _keySessionToken = 'sessionToken';
  static const _keyIdentityEnrollmentComplete = 'identityEnrollmentComplete';
  static const _keyLastIdentityVerificationAt = 'lastIdentityVerificationAt';
  static const _keyLastRiskReviewAt = 'lastRiskReviewAt';
  static const _keyKycDataConsentAccepted = 'kycDataConsentAccepted';
  static const _keyActiveRiders = 'activeRiders';
    static const _keyPendingManualClaims = 'pendingManualClaims';

  // ── Static sync API (after [init]) ─────────────────────────────────────────
    static bool get isLoggedIn =>
      _isInitialized ? (_prefs.getBool(_keyIsLoggedIn) ?? false) : false;
  static bool get isOnboarded =>
      _isInitialized
        ? (_prefs.getBool(_keyOnboardingComplete) ??
          _prefs.getBool(_keyIsOnboardedLegacy) ??
          false)
        : false;
  static bool get hasSeenCarousel =>
      _isInitialized ? (_prefs.getBool(_keyHasSeenCarousel) ?? false) : false;
    static String get phone => _isInitialized ? (_prefs.getString(_keyPhone) ?? '') : '';
    static String get userId => _isInitialized ? (_prefs.getString(_keyUserId) ?? '') : '';
    static String get policyId => _isInitialized ? (_prefs.getString(_keyPolicyId) ?? '') : '';
    static String get userZone => _isInitialized ? (_prefs.getString(_keyUserZone) ?? '') : '';
    static bool get shiftActive => _isInitialized ? (_prefs.getBool(_keyShiftActive) ?? false) : false;
    static String get shiftZone => _isInitialized ? (_prefs.getString(_keyShiftZone) ?? '') : '';
    static bool get offDutyMode => _isInitialized ? (_prefs.getBool(_keyOffDutyMode) ?? false) : false;
    static String get sessionToken => _isInitialized ? (_prefs.getString(_keySessionToken) ?? '') : '';
    static String get upiId => _isInitialized
      ? (_prefs.getString(_keyUpiId) ??
        ((phone.isNotEmpty) ? '$phone@ybl' : 'add-upi-id@ybl'))
      : ((phone.isNotEmpty) ? '$phone@ybl' : 'add-upi-id@ybl');
  static bool get identityEnrollmentComplete =>
      _isInitialized ? (_prefs.getBool(_keyIdentityEnrollmentComplete) ?? false) : false;
  static int get lastIdentityVerificationAt =>
      _isInitialized ? (_prefs.getInt(_keyLastIdentityVerificationAt) ?? 0) : 0;
  static int get lastRiskReviewAt =>
      _isInitialized ? (_prefs.getInt(_keyLastRiskReviewAt) ?? 0) : 0;

  /// User accepted in-app KYC / data-processing disclosure (DPDP-style).
  static bool get kycDataConsentAccepted =>
      _isInitialized ? (_prefs.getBool(_keyKycDataConsentAccepted) ?? false) : false;
  static List<String> get activeRiders =>
      _isInitialized ? (_prefs.getStringList(_keyActiveRiders) ?? []) : [];
  static List<String> get pendingManualClaims =>
      _isInitialized ? (_prefs.getStringList(_keyPendingManualClaims) ?? []) : [];

  /// New users must see consent before profile onboarding; completed users skip.
  static bool get needsKycDataConsent =>
      !kycDataConsentAccepted && !isOnboarded;

    static Future<void> setLoggedIn(bool v) =>
      _isInitialized ? _prefs.setBool(_keyIsLoggedIn, v) : Future.value();
  static Future<void> setOnboarded(bool v) async {
    if (!_isInitialized) return;
    await _prefs.setBool(_keyOnboardingComplete, v);
    await _prefs.setBool(_keyIsOnboardedLegacy, v);
  }

  static Future<void> setHasSeenCarousel(bool v) =>
      _isInitialized ? _prefs.setBool(_keyHasSeenCarousel, v) : Future.value();
    static Future<void> setPhone(String v) =>
      _isInitialized ? _prefs.setString(_keyPhone, v) : Future.value();
  static Future<void> setUserId(String v) =>
      _isInitialized ? _prefs.setString(_keyUserId, v) : Future.value();
  static Future<void> setPolicyId(String v) =>
      _isInitialized ? _prefs.setString(_keyPolicyId, v) : Future.value();
  static Future<void> setUserZone(String v) =>
      _isInitialized ? _prefs.setString(_keyUserZone, v) : Future.value();
  static Future<void> setShiftActive(bool v) =>
      _isInitialized ? _prefs.setBool(_keyShiftActive, v) : Future.value();
  static Future<void> setShiftZone(String v) =>
      _isInitialized ? _prefs.setString(_keyShiftZone, v) : Future.value();
  static Future<void> setOffDutyMode(bool v) =>
      _isInitialized ? _prefs.setBool(_keyOffDutyMode, v) : Future.value();
  static Future<void> setSessionToken(String v) =>
      _isInitialized ? _prefs.setString(_keySessionToken, v) : Future.value();
  static Future<void> setUpiId(String v) =>
      _isInitialized ? _prefs.setString(_keyUpiId, v) : Future.value();
  static Future<void> setIdentityEnrollmentComplete(bool v) =>
      _isInitialized ? _prefs.setBool(_keyIdentityEnrollmentComplete, v) : Future.value();
  static Future<void> setLastIdentityVerificationAt(int tsMs) =>
      _isInitialized ? _prefs.setInt(_keyLastIdentityVerificationAt, tsMs) : Future.value();
  static Future<void> setLastRiskReviewAt(int tsMs) =>
      _isInitialized ? _prefs.setInt(_keyLastRiskReviewAt, tsMs) : Future.value();
  static Future<void> setKycDataConsentAccepted(bool v) =>
      _isInitialized ? _prefs.setBool(_keyKycDataConsentAccepted, v) : Future.value();
  static Future<void> setActiveRiders(List<String> riders) =>
      _isInitialized ? _prefs.setStringList(_keyActiveRiders, riders) : Future.value();

  static List<PendingClaimQueueItem> _readAllPendingManualClaims() {
    if (!_isInitialized) return [];
    final list = _prefs.getStringList(_keyPendingManualClaims) ?? [];
    return list
        .map((c) {
          try {
            return PendingClaimQueueItem.fromJson(c);
          } catch (_) {
            return null;
          }
        })
        .whereType<PendingClaimQueueItem>()
        .toList();
  }
      
  /// Add a claim to the offline queue
  static Future<void> enqueueManualClaim(PendingClaimQueueItem item) async {
    if (!_isInitialized) return;
    final claims = _readAllPendingManualClaims();
    // Don't add if we already have one with this localId
    if (!claims.any((c) => c.localId == item.localId)) {
      claims.add(item);
      await _prefs.setStringList(
        _keyPendingManualClaims, 
        claims.map((c) => c.toJson()).toList()
      );
    }
  }

  /// Get the full typed queue for the currently logged-in user
  static Future<List<PendingClaimQueueItem>> getPendingManualClaimsQueue() async {
    final allClaims = _readAllPendingManualClaims();
    final currentUserId = userId;
    return allClaims.where((c) => c.userId == currentUserId).toList();
  }

  /// Update an existing item in the queue (e.g. after a failed retry)
  static Future<void> updateQueuedClaim(PendingClaimQueueItem item) async {
    if (!_isInitialized) return;
    final list = _prefs.getStringList(_keyPendingManualClaims) ?? [];
    final allClaims = list.map((c) {
      try {
        return PendingClaimQueueItem.fromJson(c);
      } catch (_) {
        return null;
      }
    }).whereType<PendingClaimQueueItem>().toList();

    final idx = allClaims.indexWhere((c) => c.localId == item.localId);
    if (idx >= 0) {
      allClaims[idx] = item;
      await _prefs.setStringList(
        _keyPendingManualClaims, 
        allClaims.map((c) => c.toJson()).toList()
      );
    }
  }

  /// Remove a claim from the queue (e.g. after successful sync)
  static Future<void> removeQueuedClaim(String localId) async {
    if (!_isInitialized) return;
    final list = _prefs.getStringList(_keyPendingManualClaims) ?? [];
    final allClaims = list.map((c) {
      try {
        return PendingClaimQueueItem.fromJson(c);
      } catch (_) {
        return null;
      }
    }).whereType<PendingClaimQueueItem>().toList();

    allClaims.removeWhere((c) => c.localId == localId);
    await _prefs.setStringList(
      _keyPendingManualClaims, 
      allClaims.map((c) => c.toJson()).toList()
    );
  }

    static Future<void> clearSessionToken() =>
      _isInitialized ? _prefs.remove(_keySessionToken) : Future.value();
    static Future<void> clearAll() =>
      _isInitialized ? _prefs.clear() : Future.value();

  static Future<void> setBool(String key, bool value) =>
      _isInitialized ? _prefs.setBool(key, value) : Future.value();
  static Future<void> setString(String key, String value) =>
      _isInitialized ? _prefs.setString(key, value) : Future.value();
  static Future<void> setDouble(String key, double value) =>
      _isInitialized ? _prefs.setDouble(key, value) : Future.value();
  static Future<void> setInt(String key, int value) =>
      _isInitialized ? _prefs.setInt(key, value) : Future.value();
      
    static bool? getBool(String key) => _isInitialized ? _prefs.getBool(key) : null;
    static String? getString(String key) => _isInitialized ? _prefs.getString(key) : null;
    static double? getDouble(String key) => _isInitialized ? _prefs.getDouble(key) : null;
    static int? getInt(String key) => _isInitialized ? _prefs.getInt(key) : null;

  // ── Instance API (prompt / async) ───────────────────────────────────────
  Future<void> savePhone(String phone) async => setPhone(phone);

  Future<String?> getPhone() async =>
      phone.isEmpty ? null : phone;

  Future<void> saveUserId(String id) async => setUserId(id);

  Future<String?> getUserId() async =>
      userId.isEmpty ? null : userId;

  Future<void> savePolicyId(String id) async => setPolicyId(id);

  Future<String?> getPolicyId() async =>
      policyId.isEmpty ? null : policyId;

  Future<void> saveSessionToken(String token) async => setSessionToken(token);

  Future<String?> getSessionToken() async =>
      sessionToken.isEmpty ? null : sessionToken;

  Future<void> clearSessionTokenValue() async => clearSessionToken();

  Future<void> saveUserName(String name) async =>
      setString('userName', name);

  Future<String?> getUserName() async => getString('userName');

  Future<void> saveUserZone(String zone) async => setUserZone(zone);

  Future<String?> getUserZone() async =>
      userZone.isEmpty ? null : userZone;

  Future<void> setShiftTrackingActive(bool value) async => setShiftActive(value);
  Future<bool> isShiftTrackingActive() async => shiftActive;
  Future<void> saveShiftZone(String zone) async => setShiftZone(zone);
  Future<String?> getShiftZone() async => shiftZone.isEmpty ? null : shiftZone;
    Future<void> setOffDuty(bool value) async => setOffDutyMode(value);
    Future<bool> isOffDuty() async => offDutyMode;

  Future<void> saveUserCity(String city) async =>
      setString('userCity', city);

  Future<String?> getUserCity() async => getString('userCity');

  Future<void> setOnboardingComplete(bool value) async => setOnboarded(value);

  Future<bool> isOnboardingComplete() async => isOnboarded;

  Future<void> clearDemoState() async {
    // Implement any demo specific clearing if necessary
  }

  Future<void> setLastLat(double lat) async => setDouble('lastLat', lat);
  Future<void> setLastLng(double lng) async => setDouble('lastLng', lng);
  Future<void> setPlanTier(String tier) async => setString('planTier', tier);
  Future<void> setWeeklyPremium(double premium) async => setDouble('weeklyPremium', premium);
  Future<String?> getPlanTier() async => getString('planTier');
  Future<double?> getWeeklyPremium() async => getDouble('weeklyPremium');

  Future<bool> isIdentityEnrollmentComplete() async =>
      identityEnrollmentComplete;

  Future<void> markIdentityEnrollmentComplete() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await setIdentityEnrollmentComplete(true);
    await setLastIdentityVerificationAt(now);
  }

  Future<void> markIdentityVerifiedNow() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await setLastIdentityVerificationAt(now);
  }
}
