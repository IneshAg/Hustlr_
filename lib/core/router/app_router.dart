import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/claim.dart';

import '../../features/splash/splash_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/step_up_auth_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/kyc_data_consent_screen.dart';
import '../../features/onboarding/onboarding_complete_screen.dart';
import '../../features/onboarding/onboarding_carousel_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/dashboard/trigger_status_screen.dart';
import '../../features/policy/policy_screen.dart';
import '../../features/policy/shadow_policy_screen.dart';
import '../../features/policy/premium_breakdown_screen.dart';
import '../../features/policy/payment_screen.dart';
import '../../features/policy/compound_triggers_screen.dart';
import '../../features/policy/insurance_compliance_screen.dart';
import '../../features/payment/checkout_screen.dart';
import '../../features/claims/claims_screen.dart';
import '../../features/claims/claim_detail_screen.dart';
import '../../features/claims/manual_evidence_screen.dart';
import '../../features/claims/claim_submitted_screen.dart';
import '../../features/claims/auto_explanation_screen.dart';
import '../../features/claims/appeal_claim_screen.dart';
import '../../features/claims/manual_claim_camera_screen.dart';
import '../../features/claims/manual_claim_review_screen.dart';
import '../../features/wallet/wallet_screen.dart';
import '../../features/wallet/analytics_dashboard_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/api_status_screen.dart';
import '../../features/support/support_screen.dart';
import '../../features/support/chat_screen.dart';
import '../../features/dashboard/risk_map_screen.dart';
import '../../features/admin/ml_tester_screen.dart';
import '../../features/ml_live/ml_live_screen.dart';
import '../../screens/notifications_screen.dart';
import '../../shared/widgets/bottom_nav_bar.dart';
import '../services/storage_service.dart';

// ─── Route names (type-safe) ─────────────────────────────────────────────────
class AppRoutes {
  static const root = '/';
  static const splash = '/splash';
  static const login = '/login';
  static const otp = '/otp';
  static const kycConsent = '/kyc-consent';
  static const onboarding = '/onboarding';
  static const onboardingComplete = '/onboarding/complete';
  static const carousel = '/carousel';
  static const dashboard = '/dashboard';
  static const triggerStatus = '/dashboard/triggers';
  static const policy = '/policy';
  static const shadowPolicy = '/policy/shadow';
  static const premiumBreakdown = '/policy/premium';
  static const payment = '/policy/payment';
  static const checkout = '/checkout';
  static const compoundTriggers = '/policy/compound';
  static const insuranceCompliance = '/policy/compliance';
  static const claims = '/claims';
  static const manualEvidence = '/claims/evidence';
  static const claimSubmitted = '/claims/submitted';
  static const autoExplanation = '/claims/explanation';
  static const claimDetail = '/claims/:id';
  static const claimAppeal = '/claims/:id/appeal';
  static const wallet = '/wallet';
  static const analytics = '/wallet/analytics';
  static const notifications = '/notifications';
  static const profile = '/profile';
  static const apiStatus = '/profile/api-status';
  static const support = '/support';
  static const mlTester = '/admin/ml-tester';
  static const mlLive = '/ml-live';
  static const stepUpAuth = '/step-up-auth';
  
  static const supportChat = '/support/chat';
  static const riskMap = '/dashboard/risk-map';
  static const manualClaimCamera = '/claims/evidence/camera';
  static const manualClaimReview = '/claims/evidence/review';

  static String claimDetailById(String id) => '/claims/$id';
  static String claimAppealById(String id) => '/claims/$id/appeal';
}

bool _isSamePath(String path, String route) {
  return path == route;
}

bool _isOnboardingPath(String path) {
  return _isSamePath(path, AppRoutes.carousel) ||
      _isSamePath(path, AppRoutes.kycConsent) ||
      _isSamePath(path, AppRoutes.onboarding) ||
      _isSamePath(path, AppRoutes.onboardingComplete);
}

bool _isCompliancePath(String path) {
  return _isSamePath(path, AppRoutes.insuranceCompliance);
}

bool _isPublicPath(String path) {
  return _isSamePath(path, AppRoutes.root) ||
      _isSamePath(path, AppRoutes.splash) ||
      _isSamePath(path, AppRoutes.login) ||
      _isSamePath(path, AppRoutes.otp) ||
    _isSamePath(path, AppRoutes.stepUpAuth) ||
    _isCompliancePath(path) ||
      _isOnboardingPath(path);
}

// ─── Router ──────────────────────────────────────────────────────────────────
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.login,
  redirect: (context, state) async {
    final path = state.uri.path;
    final spOnboarded = await StorageService.instance.isOnboardingComplete();
    final spLoggedIn = StorageService.isLoggedIn;

    bool hiveOnboarded = false;
    bool hiveLoggedIn = false;
    try {
      if (Hive.isBoxOpen('appData')) {
        final box = Hive.box('appData');
        hiveOnboarded = box.get('onboardingComplete', defaultValue: false) == true;
        hiveLoggedIn = box.get('isLoggedIn', defaultValue: false) == true;
      }
    } catch (_) {
      // Keep redirect resilient if Hive is unavailable.
    }

    final isOnboarded = spOnboarded || hiveOnboarded;
    final isLoggedIn = spLoggedIn || hiveLoggedIn;
    final isAuthenticated = isLoggedIn;

    // Never linger on root/splash routes.
    if (_isSamePath(path, AppRoutes.root) ||
        _isSamePath(path, AppRoutes.splash)) {
      if (!isAuthenticated) return AppRoutes.login;
      if (isOnboarded) return AppRoutes.dashboard;
      return AppRoutes.carousel;
    }

    if (!isAuthenticated) {
      // Keep unauthenticated users inside public onboarding/login routes only.
      if (!_isPublicPath(path)) return AppRoutes.login;
      return null;
    }

    if (isOnboarded) {
      // Fully onboarded users should never be routed back into auth/onboarding.
      if (_isSamePath(path, AppRoutes.splash) ||
          _isSamePath(path, AppRoutes.login) ||
          _isSamePath(path, AppRoutes.otp) ||
          _isOnboardingPath(path)) {
        return AppRoutes.dashboard;
      }
      return null;
    }

    // Authenticated but not fully onboarded: keep flow inside onboarding stack,
    // while allowing compliance review screen from KYC consent.
    if (!_isOnboardingPath(path) &&
        !_isSamePath(path, AppRoutes.stepUpAuth) &&
        !_isCompliancePath(path)) {
      return AppRoutes.carousel;
    }

    return null;
  },
  routes: [
    // ── Public ──────────────────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.root,
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.splash,
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.otp,
      builder: (context, state) {
        final phone = state.uri.queryParameters['phone'] ?? '';
        final verificationId = state.uri.queryParameters['verificationId'] ?? '';
        return OTPScreen(phone: phone, verificationId: verificationId);
      },
    ),
    GoRoute(
      path: AppRoutes.carousel,
      builder: (_, __) => const OnboardingCarouselScreen(),
    ),
    GoRoute(
      path: AppRoutes.kycConsent,
      builder: (_, __) => const KycDataConsentScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      redirect: (context, state) {
        if (StorageService.needsKycDataConsent) {
          return AppRoutes.kycConsent;
        }
        return null;
      },
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboardingComplete,
      builder: (_, __) => const OnboardingCompleteScreen(),
    ),

    // ── Shell with BottomNavBar ──────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) =>
          ScaffoldWithNav(location: state.uri.toString(), child: child),
      routes: [
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (_, __) => const DashboardScreen(),
        ),
        GoRoute(
          path: AppRoutes.policy,
          builder: (_, __) => const PolicyScreen(),
        ),
        GoRoute(
          path: AppRoutes.payment,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return PaymentScreen(checkoutData: extra);
          },
        ),
        GoRoute(
          path: AppRoutes.checkout,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>;
            return CheckoutScreen(
              amount: extra['amount'] as double,
              planName: extra['planName'] as String,
            );
          },
        ),
        GoRoute(
          path: AppRoutes.claims,
          builder: (_, __) => const ClaimsScreen(),
        ),

        GoRoute(
          path: AppRoutes.triggerStatus,
          builder: (_, __) => const TriggerStatusScreen(),
        ),
        GoRoute(
          path: AppRoutes.shadowPolicy,
          builder: (_, __) => const ShadowPolicyScreen(),
        ),
        GoRoute(
          path: AppRoutes.premiumBreakdown,
          builder: (_, __) => const PremiumBreakdownScreen(),
        ),
        GoRoute(
          path: AppRoutes.compoundTriggers,
          builder: (_, __) => const CompoundTriggersScreen(),
        ),
        GoRoute(
          path: AppRoutes.insuranceCompliance,
          builder: (_, __) => const InsuranceComplianceScreen(),
        ),
        GoRoute(
          path: AppRoutes.manualEvidence,
          builder: (_, __) => const ManualEvidenceScreen(),
        ),
        GoRoute(
          path: AppRoutes.claimSubmitted,
          builder: (context, state) {
            final extra = state.extra;
            Map<String, dynamic>? claimData;
            List<String>? imagePaths;
            if (extra is Map<String, dynamic>) {
              // New format: {'claim': {...}, 'imagePaths': [...]}
              if (extra.containsKey('claim')) {
                claimData = extra['claim'] as Map<String, dynamic>?;
                imagePaths = (extra['imagePaths'] as List?)?.cast<String>();
              } else {
                // Old format: the claim map directly
                claimData = extra;
              }
            }
            return ClaimSubmittedScreen(claimData: claimData, imagePaths: imagePaths);
          },
        ),
        GoRoute(
          path: AppRoutes.autoExplanation,
          builder: (context, state) {
            final extra = state.extra;
            final Map<String, dynamic>? payload =
                extra is Map<String, dynamic> ? extra : null;
            return AutoExplanationScreen(extra: payload);
          },
        ),
        GoRoute(
          path: AppRoutes.claimDetail,
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final extra = state.extra;
            final initialClaim = extra is Map<String, dynamic> ? extra : null;
            return ClaimDetailScreen(claimId: id, initialClaim: initialClaim);
          },
        ),
        GoRoute(
          path: AppRoutes.claimAppeal,
          builder: (context, state) {
            final claim = state.extra as Claim;
            return AppealClaimScreen(rejectedClaim: claim);
          },
        ),
        GoRoute(
          path: AppRoutes.wallet,
          builder: (_, __) => const WalletScreen(),
        ),
        GoRoute(
          path: AppRoutes.analytics,
          builder: (_, __) => const AnalyticsDashboardScreen(),
        ),
        GoRoute(
          path: AppRoutes.notifications,
          builder: (_, __) => const NotificationsScreen(),
        ),
        GoRoute(
          path: AppRoutes.profile,
          builder: (_, __) => const ProfileScreen(),
        ),
        GoRoute(
          path: AppRoutes.apiStatus,
          builder: (_, __) => const ApiStatusScreen(),
        ),
        GoRoute(
          path: AppRoutes.support,
          builder: (_, __) => const SupportScreen(),
        ),
        GoRoute(
          path: AppRoutes.supportChat,
          builder: (_, __) => const ChatScreen(),
        ),
        GoRoute(
          path: AppRoutes.riskMap,
          builder: (_, __) => const RiskMapScreen(),
        ),
        GoRoute(
          path: AppRoutes.manualClaimCamera,
          builder: (context, state) {
            final type = state.uri.queryParameters['disruptionType'] ?? 'manual';
            return ManualClaimCameraScreen(disruptionType: type);
          },
        ),
        GoRoute(
          path: AppRoutes.manualClaimReview,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            final type = extra?['disruptionType'] as String? ?? 'manual';
            final images = extra?['images'] as List<dynamic>? ?? [];
            final signal = extra?['signalStrength'] as int?;
            return ManualClaimReviewScreen(
              disruptionType: type,
              capturedImages: images.cast<XFile>(),
              signalStrength: signal,
            );
          },
        ),
      ],
    ),

    // ── Admin ────────────────────────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.mlTester,
      builder: (_, __) => const MlTesterScreen(),
    ),
    GoRoute(
      path: AppRoutes.mlLive,
      builder: (_, __) => const MLLiveScreen(),
    ),

    // ── Step-Up Biometric Auth ───────────────────────────────────────────────
    GoRoute(
      path: AppRoutes.stepUpAuth,
      builder: (context, state) {
        final reason = state.uri.queryParameters['reason'];
        final requireTwoTier =
            state.uri.queryParameters['requireTwoTier'] == 'true';
        return StepUpAuthScreen(
          triggerReason: reason,
          requireTwoTier: requireTwoTier,
        );
      },
    ),
  ],
);
