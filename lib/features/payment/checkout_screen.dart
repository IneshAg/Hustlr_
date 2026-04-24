import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../policy/razorpay_bridge_io.dart'
    if (dart.library.html) '../policy/razorpay_bridge_web.dart'
    as razorpay_bridge;

import '../../blocs/claims/claims_bloc.dart';
import '../../blocs/claims/claims_event.dart';
import '../../blocs/policy/policy_bloc.dart';
import '../../blocs/policy/policy_event.dart';
import '../../core/router/app_router.dart';
import '../../services/api_service.dart';
import '../../services/app_events.dart';
import '../../services/mock_data_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import 'package:provider/provider.dart';

import 'wallet_tab_screen.dart';

// ─── Shared colour constants ──────────────────────────────────────────────────
const Color kDarkGreen = Color(0xFF1B5E20);
const Color kLightGreen = Color(0xFFE8F5E9);
const Color kBorderGreen = Color(0xFFBBF7D0);
const Color kBgGrey = Color(0xFFF0F4F0);
const Color kTextDark = Color(0xFF0D1B0F);
const Color kTextGrey = Color(0xFF6B7280);
const Color kTextLight = Color(0xFF9CA3AF);
const Color kRed = Color(0xFFEF4444);
const Color kRedLight = Color(0xFFFEF2F2);
const Color kRedBorder = Color(0xFFFECACA);

// ─── Checkout screen ─────────────────────────────────────────────────────────
class CheckoutScreen extends StatefulWidget {
  final double amount;
  final String planName;

  const CheckoutScreen({
    required this.amount,
    required this.planName,
    super.key,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;
  int _activeDays = 0;
  bool _checkingEligibility = true;
  bool _paymentHandled = false;

  String _resolvePlanTier() {
    final rawName = widget.planName.toLowerCase();
    if (rawName.contains('full')) return 'full';
    if (rawName.contains('basic')) return 'basic';
    return 'standard';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkEligibility();
    razorpay_bridge.initializeRazorpay(
      onPaymentSuccess: (paymentId) => _verifyAndCreatePolicy(paymentId),
      onPaymentError: (message) {
        if (_paymentHandled) return;
        _paymentHandled = true;
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $message'),
            backgroundColor: Colors.red,
          ),
        );
      },
      onExternalWallet: (walletName) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('External wallet: $walletName'),
            backgroundColor: Colors.blue,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    razorpay_bridge.disposeRazorpay();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkEligibility() async {
    try {
      final userId = await StorageService.instance.getUserId();
      if (userId == null) {
        setState(() => _checkingEligibility = false);
        return;
      }

      // Demo/Persona bypass
      final isDemoUser = userId.startsWith('DEMO_') ||
          userId.startsWith('demo-') ||
          userId.startsWith('mock-') ||
          StorageService.getString('isDemoSession') == 'true';

      if (isDemoUser) {
        setState(() {
          _activeDays = 15; // Mock high experience for demo personas
          _checkingEligibility = false;
        });
        return;
      }

      final profile = await ApiService.instance.getWorkerById(userId);
      setState(() {
        _activeDays = profile['active_days'] ?? 0;
        _checkingEligibility = false;
      });
    } catch (e) {
      setState(() => _checkingEligibility = false);
    }
  }

  void _openRazorpayCheckout() async {
    setState(() => _loading = true);
    _paymentHandled = false;

    final total = widget.amount.toInt();
    final planName = widget.planName;
    final userId = await StorageService.instance.getUserId();

    const razorpayTestKey = 'rzp_test_SdS5pzapxUC7EU';

    var options = {
      'key': razorpayTestKey,
      'amount': total * 100,
      'currency': 'INR',
      'name': 'Hustlr Insurance',
      'description': '$planName Coverage',
      'theme': {
        'color': '#2E7D32',
      },
      'notes': {
        'plan': planName,
        'user_id': userId ?? 'unknown',
      },
    };

    try {
      await razorpay_bridge.openRazorpay(options);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _verifyAndCreatePolicy(String paymentId) async {
    if (_paymentHandled) return;
    _paymentHandled = true;

    try {
      final userId = await StorageService.instance.getUserId();
      if (userId == null || userId.isEmpty) {
        if (mounted) setState(() => _loading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please complete login/onboarding before payment.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final planTier = _resolvePlanTier();
      final finalPremium = widget.amount.toInt();

      final result = await ApiService.instance.createPolicy(
        userId: userId,
        planTier: planTier,
        riders: null, // Since we only get amount and planName
        paymentSource:
            'razorpay', // Payment collected externally — skip wallet deduction
      );

      NotificationService.instance.addPremiumDeducted(
        finalPremium,
        planName: widget.planName,
      );

      final isDemoUser = userId.startsWith('DEMO_') ||
          userId.startsWith('demo-') ||
          userId.startsWith('mock-') ||
          StorageService.getString('isDemoSession') == 'true';
      if (isDemoUser) {
        final mock = context.read<MockDataService>();
        mock.activatePolicy(planTier);
      }

      final policyId = result['policy']?['id'] as String?;
      if (policyId != null) {
        await StorageService.instance.savePolicyId(policyId);
      }

      AppEvents.instance.policyUpdated();
      AppEvents.instance.walletUpdated();
      if (mounted) {
        context.read<PolicyBloc>().add(LoadPolicy(userId));
        context.read<ClaimsBloc>().add(LoadClaims(userId));
      }
    } catch (e) {
      _paymentHandled = false;
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error creating policy: $e'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);
    context.go(AppRoutes.dashboard);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Payment successful! Coverage is active.',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, height: 1.4),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgGrey,
      bottomNavigationBar: _tabController.index == 0
          ? _buildStickyBottom(
              amount: widget.amount,
              buttonLabel: _isEligible
                  ? 'Proceed to Pay ₹${widget.amount.toInt()} →'
                  : 'Plan Locked',
              onTap: (_loading || !_isEligible) ? () {} : _openRazorpayCheckout,
              enabled: !_loading && _isEligible,
            )
          : null,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              if (!_checkingEligibility && _activeDays < 5) _buildProbationNotice(),
              if (!_checkingEligibility && !_isEligible) _buildEligibilityBanner(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCardUpiTab(),
                    WalletTabScreen(
                      amount: widget.amount,
                      planName: widget.planName,
                      isEligible: _isEligible,
                      activeDays: _activeDays,
                      onSwitchToCard: () {
                        _tabController.animateTo(0);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(kDarkGreen)),
              ),
            ),
        ],
      ),
    );
  }

  bool get _isEligible {
    final tier = _resolvePlanTier();
    if (tier == 'basic') return true;
    return _activeDays >= 5;
  }

  Widget _buildProbationNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, color: Colors.blue.shade700, size: 18),
              const SizedBox(width: 8),
              Text(
                'Probationary Period Active',
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Payouts for new policies are available after 7 days. You have ${_activeDays} of 5 required active days completed to unlock full benefits.',
            style: TextStyle(
              color: Colors.blue.shade900,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEligibilityBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: kRedLight,
        border: const Border(
          bottom: BorderSide(color: kRedBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: kRed, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _activeDays > 0 ? '${5 - _activeDays} days left to unlock' : 'Complete 5 active days to unlock',
                  style: const TextStyle(
                    color: kRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Only Basic Shield is available during probation.',
                  style: TextStyle(
                    color: kRed.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      color: kDarkGreen,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 24,
        left: 16,
        right: 16,
      ),
      child: Column(
        children: [
          // Top nav row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 22),
              ),
              const Text(
                'Checkout',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.lock, color: Colors.white, size: 20),
            ],
          ),
          const SizedBox(height: 24),

          // Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹${widget.amount.toInt()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/week',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Plan name
          Text(
            '${widget.planName} — Weekly Premium',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9), fontSize: 15),
          ),
          const SizedBox(height: 16),

          // Razorpay badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_rounded,
                    color: Colors.white, size: 12),
                SizedBox(width: 6),
                Text(
                  'RAZORPAY SECURED · TEST MODE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ─────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: kBorderGreen, width: 0.5)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: kDarkGreen,
        unselectedLabelColor: kTextGrey,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontSize: 14),
        indicatorColor: kDarkGreen,
        indicatorWeight: 3.0,
        indicatorPadding: const EdgeInsets.symmetric(horizontal: 16),
        onTap: (_) => setState(() {}), // refresh bottomNavBar
        tabs: const [
          Tab(text: 'Card / UPI / Netbank'),
          Tab(text: 'Hustlr Wallet'),
        ],
      ),
    );
  }

  // ── Card/UPI tab ─────────────────────────────────────────────────────────────
  Widget _buildCardUpiTab() {
    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // PAY WITH label
                  const Text(
                    'PAY WITH',
                    style: TextStyle(
                      color: kTextGrey,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_loading)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kBorderGreen),
                      ),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(color: kDarkGreen),
                          const SizedBox(height: 16),
                          const Text(
                            'Initializing Secure Payment...',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: kDarkGreen),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'If the gateway doesn\'t open automatically, tap below:',
                            style: TextStyle(fontSize: 12, color: kTextGrey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _openRazorpayCheckout,
                            child: const Text('Open Payment Gateway →',
                                style: TextStyle(
                                    decoration: TextDecoration.underline)),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // 2×2 payment method grid
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.4,
                      children: const [
                        _PaymentMethodCard(
                          icon: Icons.credit_card,
                          title: 'Card',
                          subtitle: 'Visa, MC, RuPay',
                        ),
                        _PaymentMethodCard(
                          icon: Icons.qr_code_scanner,
                          title: 'UPI',
                          subtitle: 'GPay, PhonePe',
                        ),
                        _PaymentMethodCard(
                          icon: Icons.account_balance,
                          title: 'Net Banking',
                          subtitle: 'All Indian Banks',
                        ),
                        _PaymentMethodCard(
                          icon: Icons.account_balance_wallet,
                          title: 'Wallets',
                          subtitle: 'Paytm, MobiKwik',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Test Mode card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kLightGreen,
                        border: Border.all(color: kBorderGreen, width: 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline,
                              color: kDarkGreen, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Demo Environment',
                                  style: TextStyle(
                                    color: kDarkGreen,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Payouts are enabled after a 7-day probationary period from your first policy activation.',
                                  style: TextStyle(
                                    color: kDarkGreen,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'TEST CARD: 5267 3181 8797 5449\n'
                                  'Expiry: Any Future  CVV: Any  OTP: 1234',
                                  style: TextStyle(
                                    color: kTextDark,
                                    fontSize: 11,
                                    height: 1.4,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom padding for sticky bar
                    const SizedBox(height: 100),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Sticky bottom bar (Card/UPI tab only) ────────────────────────────────────
  Widget _buildStickyBottom({
    required double amount,
    required String buttonLabel,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Payable',
                style: TextStyle(color: kTextGrey, fontSize: 13),
              ),
              Text(
                '₹${amount.toInt()}',
                style: const TextStyle(
                  color: kTextDark,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: enabled ? onTap : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: enabled ? kDarkGreen : const Color(0xFFE5E7EB),
                foregroundColor: enabled ? Colors.white : kTextLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (enabled) ...[
                    const Icon(Icons.lock, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    buttonLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Payment method card widget ───────────────────────────────────────────────
class _PaymentMethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: kDarkGreen, size: 26),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: kTextDark,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: kTextGrey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
