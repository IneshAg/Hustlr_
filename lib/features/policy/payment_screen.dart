import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'razorpay_bridge_io.dart'
    if (dart.library.html) 'razorpay_bridge_web.dart' as razorpay_bridge;

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

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic>? checkoutData;
  const PaymentScreen({super.key, this.checkoutData});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _loading = false;
  int _walletBalance = 0;
  bool _useRazorpay = true; // Razorpay vs Wallet toggle
  bool _paymentHandled = false;

  String _formatInr(num amount, {bool withSymbol = true}) {
    final value = amount.round();
    final digits = value.toString();
    if (digits.length <= 3) {
      return withSymbol ? '₹$digits' : digits;
    }

    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    final grouped = '${groups.join(',')},$last3';
    return withSymbol ? '₹$grouped' : grouped;
  }

  String _resolvePlanTier() {
    final explicit = widget.checkoutData?['planTier']?.toString().toLowerCase();
    if (explicit == 'basic' || explicit == 'standard' || explicit == 'full') {
      return explicit!;
    }

    final rawName =
        widget.checkoutData?['plan']?.toString().toLowerCase() ?? '';
    if (rawName.contains('full')) return 'full';
    if (rawName.contains('basic')) return 'basic';
    return 'standard';
  }

  @override
  void initState() {
    super.initState();
    _loadBalance();
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
    super.dispose();
  }

  void _loadBalance() async {
    try {
      final userId = await StorageService.instance.getUserId();
      if (userId == null) return;
      final data = await ApiService.instance.getWallet(userId);
      if (!mounted) return;
      setState(() {
        _walletBalance = (data['balance'] as num?)?.toInt() ?? 0;
        if (_walletBalance < 0) _walletBalance = 0;
      });
    } catch (_) {}
  }

  void _openRazorpayCheckout() async {
    setState(() => _loading = true);
    _paymentHandled = false;

    final total = (widget.checkoutData?['total'] as num?)?.toInt() ?? 49;
    final planName = widget.checkoutData?['plan'] ?? 'Standard Shield';
    final userId = await StorageService.instance.getUserId();

    // Razorpay test key (sandbox mode)
    const razorpayTestKey =
        'rzp_test_SdS5pzapxUC7EU'; // Replace with your test key

    var options = {
      'key': razorpayTestKey,
      'amount': total * 100, // Razorpay expects amount in paise
      'currency': 'INR',
      'name': 'Hustlr Insurance',
      'description': '$planName Coverage',
      'image': 'https://hustlr.in/logo.png', // Your app logo
      'prefill': {
        'contact': '', // Can add user's phone
        'email': '', // Can add user's email
      },
      'theme': {
        'color': '#2E7D32', // Your brand color
      },
      'notes': {
        'plan': planName,
        'user_id': userId ?? 'unknown',
      },
    };

    try {
      await razorpay_bridge.openRazorpay(options);
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
      final riders =
          widget.checkoutData?['riders'] as List<Map<String, dynamic>>?;
      final selectedPlanName =
          widget.checkoutData?['plan']?.toString() ?? 'Standard Shield';
      final checkoutTotal = (widget.checkoutData?['total'] as num?)?.toInt();

      final result = await ApiService.instance.createPolicy(
        userId: userId,
        planTier: planTier,
        riders: riders,
        paymentSource: 'razorpay',
      );

      final createdPolicy = result['policy'] as Map<String, dynamic>?;
      final createdPremiumRaw = createdPolicy?['weekly_premium'];
      final createdPremium = (createdPremiumRaw is num)
          ? createdPremiumRaw.round()
          : int.tryParse(createdPremiumRaw?.toString() ?? '');
      final finalPremium = checkoutTotal ?? createdPremium ?? 49;
      NotificationService.instance.addPremiumDeducted(
        finalPremium,
        planName: selectedPlanName,
      );

      // ── Sync policy state for all users (not just demo) ─────────────────
      final mock = context.read<MockDataService>();
      mock.activatePolicy(planTier); // always update dashboard mock state

      final policyId = result['policy']?['id'] as String?;
      if (policyId != null) {
        await StorageService.instance.savePolicyId(policyId);
      }

      // Fire events immediately so any mounted screens pick them up
      AppEvents.instance.policyUpdated();
      AppEvents.instance.walletUpdated();
      context.read<PolicyBloc>().add(LoadPolicy(userId));
      context.read<ClaimsBloc>().add(LoadClaims(userId));
    } catch (e) {
      if (mounted) {
        _paymentHandled = false;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating policy: $e'),
            backgroundColor: Colors.red,
          ),
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
            color: Colors.white,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _payWithWallet() async {
    setState(() => _loading = true);
    try {
      final userId = await StorageService.instance.getUserId();
      if (userId == null) throw Exception('User not logged in');

      final total = (widget.checkoutData?['total'] as num?)?.toInt() ?? 49;

      if (_walletBalance < total) {
        throw Exception('Insufficient wallet balance');
      }

      // Deduct from wallet
      final planTier = _resolvePlanTier();

      // Create policy
      final result = await ApiService.instance.createPolicy(
        userId: userId,
        planTier: planTier,
      );

      final selectedPlanName =
          widget.checkoutData?['plan']?.toString() ?? 'Standard Shield';
      NotificationService.instance.addPremiumDeducted(
        total,
        planName: selectedPlanName,
      );

      // ── Sync policy state for all users (not just demo) ─────────────────
      final mock = context.read<MockDataService>();
      mock.activatePolicy(planTier); // always update dashboard mock state

      final policyId = result['policy']?['id'] as String?;
      if (policyId != null) {
        await StorageService.instance.savePolicyId(policyId);
      }

      // Fire events immediately before navigation
      AppEvents.instance.policyUpdated();
      AppEvents.instance.walletUpdated();
      context.read<PolicyBloc>().add(LoadPolicy(userId));
      context.read<ClaimsBloc>().add(LoadClaims(userId));

      if (!mounted) return;
      setState(() => _loading = false);
      context.go(AppRoutes.dashboard);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Payment successful! Coverage is active.',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = (widget.checkoutData?['total'] as num?)?.toInt() ?? 49;
    final planCost =
        (widget.checkoutData?['planCost'] as num?)?.toInt() ?? total;
    final rawRiders =
        widget.checkoutData?['riders'] as List<dynamic>? ?? const [];
    final riders = rawRiders
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
    final riderTotal = riders.fold<int>(
      0,
      (sum, r) => sum + ((r['cost'] as num?)?.toInt() ?? 0),
    );
    final planName = widget.checkoutData?['plan'] ?? 'Standard Shield';
    final bg = const Color(0xFFF4F7F4);
    final green = const Color(0xFF2E7D32);
    final deep = const Color(0xFF163A1D);
    final muted = const Color(0xFF667085);
    final walletShort = _walletBalance >= total;
    final formattedTotal = _formatInr(total);
    final formattedWallet = _formatInr(_walletBalance);
    final shortfall = _formatInr(total - _walletBalance);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: green,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Colors.white),
        ),
        title: Column(
          children: [
            const Text(
              'Checkout',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              'hustlr.app',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Hero header
          Container(
            width: double.infinity,
            color: green,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              children: [
                Text(
                  formattedTotal,
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  planName,
                  style: TextStyle(
                    fontSize: 17,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),

          // Payment method selection
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x11000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        _buildMethodTab(
                          active: _useRazorpay,
                          icon: Icons.credit_card_rounded,
                          label: 'Card/UPI/Netbanking',
                          onTap: () => setState(() => _useRazorpay = true),
                        ),
                        _buildMethodTab(
                          active: !_useRazorpay,
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'Wallet ($formattedWallet)',
                          onTap: () => setState(() => _useRazorpay = false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                            sizeFactor: animation,
                            axisAlignment: -1,
                            child: child),
                      );
                    },
                    child: _useRazorpay
                        ? Column(
                            key: const ValueKey('razorpay-mode'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: const Color(0xFFE6EAE8)),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x10000000),
                                      blurRadius: 16,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE9F4EA),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Icon(Icons.lock_rounded,
                                              size: 22,
                                              color: Color(0xFF2E7D32)),
                                        ),
                                        const SizedBox(width: 12),
                                        const Expanded(
                                          child: Text(
                                            'Razorpay Secure Checkout',
                                            style: TextStyle(
                                                fontSize: 21,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF163A1D)),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'You will be redirected to a secure Razorpay payment page to complete this purchase.',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: muted,
                                          height: 1.35),
                                    ),
                                    const SizedBox(height: 14),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE6F1FF),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'SANDBOX MODE - TEST PAYMENTS ONLY',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF1E5FAF),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Supported payment methods:',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: deep,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _paymentMethodChip(
                                      'Credit/Debit Card', Icons.credit_card),
                                  _paymentMethodChip(
                                      'UPI', Icons.account_balance),
                                  _paymentMethodChip(
                                      'Netbanking', Icons.language),
                                  _paymentMethodChip(
                                      'Wallets', Icons.account_balance_wallet),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Popular cards & UPI apps',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: const [
                                  _BrandBadge(label: 'Visa'),
                                  _BrandBadge(label: 'Mastercard'),
                                  _BrandBadge(label: 'RuPay'),
                                  _BrandBadge(label: 'GPay'),
                                  _BrandBadge(label: 'PhonePe'),
                                  _BrandBadge(label: 'Paytm'),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF4DF),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFFF2D29A)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.info_outline_rounded,
                                            size: 18, color: Color(0xFF9D5A00)),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Test Mode Info',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF9D5A00),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Use these test card details:\nCard: 5267 3181 8797 5449\nExpiry: Any future date\nCVV: Any 3 digits\nOTP: 1234',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF8A4E00),
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            key: const ValueKey('wallet-mode'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: const Color(0xFFE6EAE8)),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x10000000),
                                      blurRadius: 16,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE9F4EA),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                          Icons.account_balance_wallet_rounded,
                                          size: 22,
                                          color: Color(0xFF2E7D32)),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Hustlr Wallet',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: deep,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Balance: $formattedWallet',
                                      style: const TextStyle(
                                        fontSize: 38,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF2E7D32),
                                        height: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      walletShort
                                          ? 'You have enough wallet balance for this payment.'
                                          : 'Available for payment',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_walletBalance < total)
                                Container(
                                  margin: const EdgeInsets.only(top: 14),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1F2),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: const Color(0xFFF4C8CD)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded,
                                          size: 18, color: Color(0xFFB42318)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Insufficient balance. Add $shortfall more.',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFFB42318),
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x15000000),
                  blurRadius: 18,
                  offset: Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (riderTotal > 0)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8F7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE6EAE8)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Amount breakdown',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: muted,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Base plan',
                                  style: TextStyle(fontSize: 12, color: muted)),
                              Text(_formatInr(planCost),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Add-ons (${riders.length})',
                                  style: TextStyle(fontSize: 12, color: muted)),
                              Text('+${_formatInr(riderTotal)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total payable',
                          style: TextStyle(fontSize: 13, color: muted)),
                      Text(formattedTotal,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF163A1D))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _loading
                          ? null
                          : (_useRazorpay
                              ? _openRazorpayCheckout
                              : (_walletBalance < total
                                  ? null
                                  : _payWithWallet)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFD5D9D6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    _useRazorpay
                                        ? 'Proceed to Pay $formattedTotal'
                                        : 'Pay with Wallet',
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (_useRazorpay) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded,
                                      size: 18),
                                ],
                              ],
                            ),
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

  Widget _buildMethodTab({
    required bool active,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE9F4EA) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color:
                    active ? const Color(0xFF2E7D32) : const Color(0xFF98A2B3),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFF98A2B3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentMethodChip(String label, IconData icon) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth <= 90;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 10,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFDDE3DF)),
          ),
          child: isCompact
              ? Icon(icon, size: 16, color: const Color(0xFF57636C))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: const Color(0xFF57636C)),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF344054),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _BrandBadge extends StatelessWidget {
  final String label;

  const _BrandBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF475467),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
