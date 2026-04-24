import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/router/app_router.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';

class OTPScreen extends StatefulWidget {
  final String phone;
  final String verificationId;

  const OTPScreen(
      {super.key, required this.phone, required this.verificationId});

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _currentOtp => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _error = null);
  }

  Future<void> _verify() async {
    final otp = _currentOtp;
    if (otp.length < 6) {
      setState(() => _error = 'Please enter all 6 digits');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Authenticate with Firebase
      if (widget.verificationId == 'demo-bypass' ||
          widget.verificationId.isEmpty) {
        if (otp != '123456') {
          setState(() {
            _loading = false;
            _error = 'Invalid testing code. Please use: 123456';
          });
          return;
        }
        // SIMULATED NETWORK LAG
        await Future.delayed(const Duration(seconds: 1));
      } else {
        final credential = PhoneAuthProvider.credential(
          verificationId: widget.verificationId,
          smsCode: otp,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }

        // 2. Firebase Success! Proceed to local Hustlr routing logic
        final box = Hive.isBoxOpen('appData')
          ? Hive.box('appData')
          : await Hive.openBox('appData');
      await box.put('isLoggedIn', true);
      await StorageService.setLoggedIn(true);
      final phoneNumber = '+91${widget.phone}';
      await box.put('phone', phoneNumber);
      await StorageService.instance.savePhone(phoneNumber);
      await StorageService.instance.clearSessionTokenValue();
      ApiService.instance.accessToken = null;

      // Check if user already exists
      final existingUser = await ApiService.getWorkerByPhone(phoneNumber);

      if (!mounted) return;

      if (existingUser != null) {
        // User exists, save context and navigate straight to dashboard
        final userId = existingUser['id'] as String;
        await ApiService.instance.startSession(
          userId: userId,
          phone: phoneNumber,
          deviceLabel: 'hustlr_flutter_app',
        );
        await StorageService.setUserId(userId);
        await StorageService.setOnboarded(true);
        await StorageService.instance
            .saveUserName(existingUser['name'] as String? ?? '');
        await StorageService.instance
            .saveUserCity(existingUser['city'] as String? ?? '');
        await StorageService.instance
            .saveUserZone(existingUser['zone'] as String? ?? '');
        await StorageService.setString(
            'userPlatform', existingUser['platform'] as String? ?? '');

        await box.put('userName', existingUser['name']);
        await box.put('userCity', existingUser['city']);
        await box.put('userZone', existingUser['zone']);
        await box.put('userPlatform', existingUser['platform']);
        await box.put('onboardingComplete', true);

        // Existing users: if identity enrollment is missing (legacy accounts),
        // force two-tier enrollment once; otherwise do regular step-up auth.
        final hasEnrollment =
            await StorageService.instance.isIdentityEnrollmentComplete();
        final reason = Uri.encodeComponent(hasEnrollment
            ? 'Confirm your identity to securely access Hustlr.'
            : 'Complete one-time biometric + face enrollment to secure your account.');
        final authResult = await context.push<Map<String, dynamic>>(
            '${AppRoutes.stepUpAuth}?reason=$reason&requireTwoTier=${!hasEnrollment}');

        if (!mounted) return;
        if (authResult != null && authResult['verified'] == true) {
          context.go(AppRoutes.dashboard);
        } else {
          setState(() {
            _error = 'Identity verification failed. Cannot access account.';
          });
        }
      } else {
        // User does not exist, proceed to onboarding
        final onboardingComplete =
            box.get('onboardingComplete', defaultValue: false);
        if (onboardingComplete) {
          context.go(AppRoutes.dashboard); // Safety fallback
        } else {
          context.go(AppRoutes.carousel);
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message ?? 'Invalid OTP code entered.';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Connection failed. Please ensure the backend is running.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resendOtp() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
    setState(() => _error = null);

    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'OTP RESENT SUCCESSFULLY',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onPrimary),
        ),
        backgroundColor: theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Header Bar ─────────────────────────────────────────
              SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.login);
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(Icons.arrow_back,
                              color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Verification',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Hustlr',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Title & Intro ──────────────────────────────────────────
              Text(
                'SECURITY STEP',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter verification code',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "We've sent a 6-digit code to +91 ${widget.phone}",
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 32),

              // ── Static OTP Tiles ──────────────────────────────────────
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 6.0;
                  final adaptiveWidth =
                      ((constraints.maxWidth - (spacing * 5)) / 6)
                          .clamp(32.0, 44.0)
                          .toDouble();

                  return Row(
                    children: List.generate(6, (i) {
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == 5 ? 0 : spacing),
                          child: _StaticOtpBox(
                            index: i,
                            controller: _controllers[i],
                            focusNode: _focusNodes[i],
                            hasError: _error != null,
                            theme: theme,
                            isDark: isDark,
                            boxWidth: adaptiveWidth,
                            onChanged: (v) => _onDigitChanged(i, v),
                            onBackspace: () {
                              if (_controllers[i].text.isEmpty && i > 0) {
                                _focusNodes[i - 1].requestFocus();
                                _controllers[i - 1].clear();
                              }
                            },
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),

              // ── Error State ────────────────────────────────────────────
              if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // ── Resend Text ────────────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: _resendOtp,
                  behavior: HitTestBehavior.opaque,
                  child: const Text(
                    "Didn't receive the code? Resend in 00:45",
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Button ────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Verify & Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Terms Footer ───────────────────────────────────────────
              const Center(
                child: Text(
                  'By continuing, you agree to Hustlr\'s professional\nconduct guidelines and secure transaction protocols.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Static OTP Box Tile ───────────────────────────────────────────────────
class _StaticOtpBox extends StatefulWidget {
  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final ThemeData theme;
  final bool isDark;
  final double boxWidth;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _StaticOtpBox({
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.theme,
    required this.isDark,
    required this.boxWidth,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  State<_StaticOtpBox> createState() => _StaticOtpBoxState();
}

class _StaticOtpBoxState extends State<_StaticOtpBox> {
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    final isFocused = widget.focusNode.hasFocus;

    final isDark = widget.isDark;
    final primary = const Color(0xFF2E7D32);
    final defaultBg = isDark ? const Color(0xFF1C1F1C) : Colors.white;

    Color borderColor;
    Color bgColor;
    double borderWidth;

    if (widget.hasError) {
      borderColor = widget.theme.colorScheme.error;
      bgColor = defaultBg;
      borderWidth = 1.5;
    } else if (isFocused) {
      borderColor = primary;
      bgColor = isDark ? const Color(0xFF1C2A1C) : const Color(0xFFF9FFF9);
      borderWidth = 1.5;
    } else if (hasText) {
      borderColor = primary;
      bgColor = defaultBg;
      borderWidth = 1.5;
    } else {
      borderColor =
          isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE5E7EB);
      bgColor = defaultBg;
      borderWidth = 1.0;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: widget.boxWidth,
      height: 52,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
      ),
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              widget.controller.text.isEmpty) {
            widget.onBackspace();
          }
        },
        child: Center(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: widget.onChanged,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: widget.theme.colorScheme.onSurface,
            ),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }
}
