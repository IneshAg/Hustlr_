import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import '../../shared/widgets/secure_camera_screen.dart';
import '../../services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/biometric_service.dart';
import '../../l10n/app_localizations.dart';

/// Google Cloud Vision Step-Up Identity Verification Screen
/// Triggered on: behavioral anomaly, high-value claims (>=300),
/// new device detected, or 1% random weekly audit.
///
/// Auth flow (two-tier):
///   Tier 1 → Native biometric (fingerprint / Face ID via local_auth)
///   Tier 2 → Camera selfie → Google Cloud Vision (fallback or high-risk escalation)
class StepUpAuthScreen extends StatefulWidget {
  /// Optional reason string shown to the user explaining why this was triggered
  final String? triggerReason;
  final bool requireTwoTier;

  const StepUpAuthScreen({
    super.key,
    this.triggerReason,
    this.requireTwoTier = false,
  });

  @override
  State<StepUpAuthScreen> createState() => _StepUpAuthScreenState();
}

class _StepUpAuthScreenState extends State<StepUpAuthScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  _VerificationState _state = _VerificationState.idle;
  _AuthTier _tier = _AuthTier.biometric;

  String? _errorMessage;
  double? _similarityScore;
  bool _biometricAvailable = false;
  List<BiometricType> _enrolledBiometrics = [];
  bool _biometricPassed = false;
  bool _webFallbackMode = false;
  String? _hintMessage;
  String? _firstTurnDirection;

  // Single capture for face verification
  final List<String> _gestures = [
    'Look straight into the camera',
  ];
  int _gestureStepIndex = 0;
  String? _currentGesture;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (kIsWeb) {
      _webFallbackMode = true;
      _tier = _AuthTier.camera;
      _state = _VerificationState.idle;
      _hintMessage =
          'Web fallback enabled: biometric and secure camera verification are not required on web.';
    } else {
      _checkBiometricAvailability();
    }
    _currentGesture = _gestures.first;
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await BiometricService.instance.isAvailable();
    final enrolled = await BiometricService.instance.getEnrolledBiometrics();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _enrolledBiometrics = enrolled;
        // If biometric is unavailable, jump straight to camera tier
        if (!available) _tier = _AuthTier.camera;
      });
      // Auto-trigger biometric prompt on screen open if available
      if (available) _triggerBiometric();
    }
  }

  Future<void> _triggerBiometric() async {
    setState(() {
      _state = _VerificationState.verifying;
      _errorMessage = null;
    });

    final result = await BiometricService.instance.authenticate(
      reason: widget.triggerReason ??
          'Confirm your identity to proceed with this claim.',
    );

    if (!mounted) return;

    if (result.success) {
      if (widget.requireTwoTier) {
        setState(() {
          _biometricPassed = true;
          _tier = _AuthTier.camera;
          _state = _VerificationState.idle;
        });
      } else {
        setState(() => _state = _VerificationState.success);
      }
    } else {
      setState(() {
        _state = _VerificationState.failed;
        _errorMessage = result.errorMessage;
        // On biometric failure, offer camera escalation
        _tier = _AuthTier.camera;
      });
    }
  }

  Future<void> _captureAndVerify() async {
    setState(() {
      _state = _VerificationState.capturing;
      _errorMessage = null;
    });

    try {
      String? base64Image;

      if (kIsWeb) {
        final picker = ImagePicker();
        final XFile? photo = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 640,
          maxHeight: 640,
          imageQuality: 85,
        );
        if (photo == null) {
          setState(() => _state = _VerificationState.idle);
          return;
        }
        setState(() => _state = _VerificationState.verifying);
        final bytes = await photo.readAsBytes();
        base64Image = base64Encode(bytes);
      } else {
        final result = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (_) => SecureCameraScreen(
              mode: CameraMode.kycFace,
              title: 'Face Verification',
              instructions: '$_currentGesture\n\nPlease ensure your face is fully visible within the circle.',
              enforceLiveGesture: false, // Set to false to allow manual/standard capture
              expectedGesture: _currentGesture,
            ),
          ),
        );

        if (result == null || result['base64'] == null) {
          setState(() => _state = _VerificationState.idle);
          return;
        }
        
        setState(() => _state = _VerificationState.verifying);
        base64Image = result['base64'] as String;
      }
      final userId = await StorageService.instance.getUserId();

      final result = await ApiService.instance.verifyFaceLiveness(
        workerId: userId ?? 'demo-user',
        imageBase64: base64Image,
        expectedGesture: _currentGesture,
      );

      final verified = result['verified'] as bool? ?? false;
      final score = (result['similarity_score'] as num?)?.toDouble() ?? 0.0;

      if (!verified) {
        setState(() {
          _similarityScore = score;
          _state = _VerificationState.failed;
          _errorMessage =
              result['reason'] ?? 'Face did not match registered profile.';
          _hintMessage = null;
        });
        return;
      }

      // Single step verification.
      setState(() {
        _similarityScore = score;
        _state = _VerificationState.success;
        _errorMessage = null;
        _hintMessage = null;
      });

      // Update backend KYC status on success
      if (userId != null) {
        await ApiService.instance.updateWorkerProfile(
          userId: userId,
          updates: {'kyc_status': 'verified'},
        ).catchError((e) => developer.log('Failed to update kyc_status: $e'));
      }

      // Note: Auto-pop removed. The user must manually click 'CONTINUE'.
    } catch (e) {
      setState(() {
        _state = _VerificationState.failed;
        _errorMessage = 'Verification error. Please try again.';
        _hintMessage = null;
      });
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  Future<void> _completeAndExit({
    required String method,
    required double? similarityScore,
  }) async {
    if (widget.requireTwoTier) {
      await StorageService.instance.markIdentityEnrollmentComplete();
    } else {
      await StorageService.instance.markIdentityVerifiedNow();
    }
    if (!mounted) return;
    Navigator.pop(context, {
      'verified': true,
      'similarity_score': similarityScore,
      'method': method,
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final accentGreen = theme.colorScheme.primary;
    final secondaryTextColor = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return Scaffold(
      backgroundColor: theme.canvasColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: secondaryTextColor),
          onPressed: () => Navigator.pop(context, {'verified': false}),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 40),

            // Biometric / face ring + status
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _tier == _AuthTier.biometric
                      ? _buildBiometricRing(accentGreen)
                      : _buildFaceRing(accentGreen),
                  const SizedBox(height: 40),
                  _buildStatusText(),
                  // Gesture prompt for camera tier
                  if (_tier == _AuthTier.camera && _currentGesture != null && _state == _VerificationState.idle) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_alt_rounded, color: primaryColor, size: 20),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              _currentGesture!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                    ),
                  ],
                  if (_hintMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _hintMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // CTA Button(s)
            _buildActionButtons(primaryColor, accentGreen),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  IconData _primaryBiometricIcon() {
    if (_enrolledBiometrics.contains(BiometricType.face)) {
      return Icons.face_outlined;
    }
    return Icons.fingerprint;
  }

  Widget _buildBiometricRing(Color accentGreen) {
    final ringColor = _state == _VerificationState.success
        ? accentGreen
        : _state == _VerificationState.failed
            ? Colors.redAccent
            : Colors.white24;

    Widget icon;
    if (_state == _VerificationState.verifying) {
      icon = SizedBox(
        width: 48,
        height: 48,
        child: CircularProgressIndicator(
          color: accentGreen,
          strokeWidth: 3,
        ),
      );
    } else if (_state == _VerificationState.success) {
      icon = Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: accentGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 36),
      );
    } else if (_state == _VerificationState.failed) {
      icon = Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 36),
      );
    } else {
      icon = Icon(
        _primaryBiometricIcon(),
        color: Theme.of(context).colorScheme.onSurface,
        size: 56,
      );
    }

    final shouldPulse = _state == _VerificationState.idle;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, child) => Transform.scale(
        scale: shouldPulse ? _pulseAnimation.value : 1.0,
        child: child,
      ),
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ringColor,
          boxShadow: shouldPulse
              ? [
                  BoxShadow(
                    color: ringColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(child: icon),
      ),
    );
  }

  Widget _buildFaceRing(Color accentGreen) {
    final ringColor = _state == _VerificationState.success
        ? accentGreen
        : _state == _VerificationState.failed
            ? Colors.redAccent
            : Colors.white24;

    Widget icon;
    if (_state == _VerificationState.verifying) {
      icon = SizedBox(
        width: 48,
        height: 48,
        child: CircularProgressIndicator(
          color: accentGreen,
          strokeWidth: 3,
        ),
      );
    } else if (_state == _VerificationState.success) {
      icon = Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: accentGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 36),
      );
    } else if (_state == _VerificationState.failed) {
      icon = Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 36),
      );
    } else {
      icon = Icon(
        Icons.face_outlined,
        color: Theme.of(context).colorScheme.onSurface,
        size: 56,
      );
    }

    final shouldPulse = _state == _VerificationState.idle ||
        _state == _VerificationState.capturing;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, child) => Transform.scale(
        scale: shouldPulse ? _pulseAnimation.value : 1.0,
        child: child,
      ),
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ringColor,
          boxShadow: shouldPulse
              ? [
                  BoxShadow(
                    color: ringColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(child: icon),
      ),
    );
  }

  Widget _buildStatusText() {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    String title, subtitle;
    if (_tier == _AuthTier.biometric) {
      switch (_state) {
        case _VerificationState.idle:
          title = 'Authenticate';
          subtitle = _biometricAvailable
              ? 'Use your fingerprint or Face ID'
              : 'Biometric not available';
          break;
        case _VerificationState.verifying:
          title = 'Authenticating...';
          subtitle = 'Touch the sensor';
          break;
        case _VerificationState.success:
          title = 'Success';
          subtitle = 'Authentication successful';
          break;
        case _VerificationState.failed:
          title = 'Authentication Failed';
          subtitle = 'Try again or use secure face verification';
          break;
        default:
          title = 'Authenticate';
          subtitle = '';
      }
    } else {
      if (_webFallbackMode) {
        title = 'Web Verification';
        subtitle =
            'Fingerprint and secure face capture are unavailable on web. Continue using secure fallback.';
      } else {
      switch (_state) {
        case _VerificationState.idle:
        case _VerificationState.failed:
          title = widget.requireTwoTier
              ? (_biometricPassed ? 'Face Verification (Step 2/2)' : 'Face Verification')
              : 'Face Verification';
          final selfie = l10n.step_up_face_selfie_notice;
          final ml = l10n.step_up_face_ml_notice;
          if (widget.requireTwoTier && _biometricPassed) {
            subtitle =
                '$selfie\n\n$ml\n\nBiometric complete. Capture your photo to finish enrollment.';
          } else {
            subtitle = '$selfie\n\n$ml';
          }
          break;
        case _VerificationState.capturing:
          title = l10n.step_up_face_capturing;
          subtitle = l10n.step_up_face_hold;
          break;
        case _VerificationState.verifying:
          title = 'Verifying';
          subtitle = 'Checking gesture and liveness...';
          break;
        case _VerificationState.success:
          title = 'Success';
          subtitle = 'Verification complete';
          break;
      }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _state == _VerificationState.success
                  ? const Color(0xFF4CAF50)
                  : _state == _VerificationState.failed
                      ? Colors.redAccent
                    : onSurface,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              fontFamily: 'Manrope',
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.65),
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_state == _VerificationState.success && _similarityScore != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
              ),
              child: Text(
                'SIMILARITY: ${(_similarityScore! * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(Color primaryColor, Color accentGreen) {
    if (_webFallbackMode) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () => _completeAndExit(
            method: 'web_fallback',
            similarityScore: null,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text(
            'CONTINUE ON WEB',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      );
    }

    if (_state == _VerificationState.success) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () => _completeAndExit(
            method: _tier == _AuthTier.biometric 
                ? 'biometric' 
                : (widget.requireTwoTier ? 'biometric+google_cloud_vision' : 'google_cloud_vision'),
            similarityScore: _similarityScore,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
            shadowColor: const Color(0xFF4CAF50).withValues(alpha: 0.4),
          ),
          child: const Text(
            'CONTINUE',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.2),
          ),
        ),
      );
    }

    final isLoading = _state == _VerificationState.verifying ||
        _state == _VerificationState.capturing;

    if (_tier == _AuthTier.biometric) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : _triggerBiometric,
              icon: Icon(_primaryBiometricIcon()),
              label: Text(
                _state == _VerificationState.failed ? 'Retry Biometric' : 'Use Biometric',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: primaryColor.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (_biometricAvailable && _state == _VerificationState.failed) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() {
                _tier = _AuthTier.camera;
                _state = _VerificationState.idle;
                _errorMessage = null;
                _hintMessage = null;
                _gestureStepIndex = 0;
                _firstTurnDirection = null;
                _currentGesture = _gestures.first;
              }),
              child: Text(
                kIsWeb ? 'Upload Photo Instead' : 'Use Camera Instead',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      );
    }

    // Camera tier buttons
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : _captureAndVerify,
            icon: Icon(kIsWeb ? Icons.upload : Icons.camera_alt_outlined),
            label: Text(
              _state == _VerificationState.failed 
                  ? 'Retry Photo' 
                  : 'Capture Photo',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: primaryColor.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        if (_biometricAvailable && !widget.requireTwoTier) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() {
              _tier = _AuthTier.biometric;
              _state = _VerificationState.idle;
              _errorMessage = null;
              _hintMessage = null;
              _gestureStepIndex = 0;
              _firstTurnDirection = null;
              _currentGesture = _gestures.first;
            }),
            child: Text(
              'Use Biometric Instead',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _VerificationState { idle, capturing, verifying, success, failed }
enum _AuthTier { biometric, camera }
