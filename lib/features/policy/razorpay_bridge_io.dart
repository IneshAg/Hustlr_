import 'package:razorpay_flutter/razorpay_flutter.dart';

Razorpay? _razorpay;

/// Native (iOS/Android/desktop VM): real Razorpay SDK.
void initializeRazorpay({
  required void Function(String paymentId) onPaymentSuccess,
  required void Function(String message) onPaymentError,
  required void Function(String walletName) onExternalWallet,
}) {
  _razorpay = Razorpay();
  _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
    onPaymentSuccess(r.paymentId ?? 'unknown');
  });
  _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
    onPaymentError(r.message ?? 'Payment failed');
  });
  _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
    onExternalWallet(r.walletName ?? '');
  });
}

Future<void> openRazorpay(Map<String, dynamic> options) async {
  final r = _razorpay;
  if (r == null) {
    throw StateError('Razorpay not initialized');
  }
  r.open(options);
}

void disposeRazorpay() {
  _razorpay?.clear();
  _razorpay = null;
}
