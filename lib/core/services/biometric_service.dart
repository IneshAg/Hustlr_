import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

/// BiometricService — wraps local_auth for fingerprint / Face ID step-up checks.
///
/// Usage:
///   final result = await BiometricService.instance.authenticate(
///     reason: 'Confirm your identity to submit this claim',
///   );
///   if (result.success) { ... }
class BiometricService {
  BiometricService._();
  static final instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// Returns true if the device hardware supports any biometric (fingerprint
  /// or face) AND the user has enrolled at least one credential.
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;

      final enrolledBiometrics = await _auth.getAvailableBiometrics();
      return enrolledBiometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Returns the list of enrolled biometric types so the UI can
  /// show the right icon (fingerprint vs face).
  Future<List<BiometricType>> getEnrolledBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Triggers the native biometric prompt.
  ///
  /// [reason] — shown inside the system dialog.
  /// Returns a [BiometricResult] with success flag and optional error.
  Future<BiometricResult> authenticate({
    required String reason,
    bool stickyAuth = true,    // keep prompt alive if user switches apps
    bool sensitiveTransaction = true,
  }) async {
    try {
      final available = await isAvailable();
      if (!available) {
        return BiometricResult(
          success: false,
          errorCode: 'NOT_AVAILABLE',
          errorMessage: 'No biometric credentials enrolled on this device.',
        );
      }

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          stickyAuth: stickyAuth,
          sensitiveTransaction: sensitiveTransaction,
          useErrorDialogs: true,
          biometricOnly: false, // allow PIN fallback
        ),
      );

      return BiometricResult(success: authenticated);
    } on PlatformException catch (e) {
      return BiometricResult(
        success: false,
        errorCode: e.code,
        errorMessage: _friendlyError(e.code),
      );
    } catch (e) {
      return BiometricResult(
        success: false,
        errorCode: 'UNKNOWN',
        errorMessage: 'Biometric check failed. Please try again.',
      );
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case auth_error.notAvailable:
        return 'Biometrics not available on this device.';
      case auth_error.notEnrolled:
        return 'No fingerprint or face enrolled. Please set up in device Settings.';
      case auth_error.lockedOut:
        return 'Too many failed attempts. Try again in 30 seconds.';
      case auth_error.permanentlyLockedOut:
        return 'Biometrics locked. Use PIN or password in device Settings to unlock.';
      case auth_error.passcodeNotSet:
        return 'Device lock screen not set. Enable PIN/password first.';
      default:
        return 'Biometric authentication failed.';
    }
  }
}

class BiometricResult {
  final bool success;
  final String? errorCode;
  final String? errorMessage;

  const BiometricResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
  });
}
