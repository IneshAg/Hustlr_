import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter/services.dart';
import 'dart:developer' as developer;

class BiometricService {
  static final BiometricService instance = 
      BiometricService._internal();
  BiometricService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      developer.log('BiometricService: canCheckBiometrics = $canCheck');
      final isSupported = await _auth.isDeviceSupported();
      developer.log('BiometricService: isDeviceSupported = $isSupported');
      final available = canCheck && isSupported;
      developer.log('BiometricService: isAvailable = $available');
      return available;
    } catch (e) {
      developer.log('BiometricService: isAvailable error = $e');
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableTypes() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      developer.log('BiometricService: available types = $types');
      return types;
    } catch (e) {
      developer.log('BiometricService: getAvailableTypes error = $e');
      return [];
    }
  }

  /// Prompt the device biometric dialog.
  /// Returns true if authenticated successfully.
  Future<BiometricResult> authenticate({
    String reason = 'Confirm your identity',
  }) async {
    developer.log('BiometricService: authenticate called with reason: $reason');
    final available = await isAvailable();
    developer.log('BiometricService: authenticate - available = $available');
    
    if (!available) {
      developer.log('BiometricService: authenticate - not available, returning error');
      return BiometricResult(
        success: false,
        message: 'Biometrics not available on this device',
        notAvailable: true,
      );
    }

    try {
      developer.log('BiometricService: authenticate - calling _auth.authenticate');
      final didAuth = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth:   true,
          biometricOnly: false,  // allow PIN fallback
          useErrorDialogs: true,
        ),
      );
      developer.log('BiometricService: authenticate - didAuth = $didAuth');

      return BiometricResult(
        success: didAuth,
        message: didAuth
            ? 'Authenticated successfully'
            : 'Authentication failed',
      );

    } on PlatformException catch (e) {
      developer.log('BiometricService: authenticate - PlatformException: ${e.code}, ${e.message}');
      if (e.code == auth_error.notAvailable) {
        return BiometricResult(
          success:      false,
          message:      'Biometrics not enrolled on this device',
          notAvailable: true,
        );
      }
      if (e.code == auth_error.lockedOut ||
          e.code == auth_error.permanentlyLockedOut) {
        return BiometricResult(
          success: false,
          message: 'Too many attempts — device locked',
        );
      }
      return BiometricResult(
        success: false,
        message: 'Authentication error: ${e.message}',
      );
    } catch (e) {
      developer.log('BiometricService: authenticate - unexpected error: $e');
      return BiometricResult(
        success: false,
        message: 'Unexpected error: $e',
      );
    }
  }
}

class BiometricResult {
  final bool success;
  final String message;
  final bool notAvailable;

  BiometricResult({
    required this.success,
    required this.message,
    this.notAvailable = false,
  });
}
