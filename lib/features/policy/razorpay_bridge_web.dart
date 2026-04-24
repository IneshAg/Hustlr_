import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

void Function(String paymentId)? _onPaymentSuccess;
void Function(String message)? _onPaymentError;
void Function(String walletName)? _onExternalWallet;

Future<void> _ensureCheckoutScriptLoaded() async {
  final hasRazorpay = js.context.hasProperty('Razorpay');
  if (hasRazorpay) return;

  final completer = Completer<void>();
  final script = html.ScriptElement()
    ..src = 'https://checkout.razorpay.com/v1/checkout.js'
    ..type = 'text/javascript'
    ..async = true;

  script.onLoad.first.then((_) {
    if (!completer.isCompleted) completer.complete();
  });
  script.onError.first.then((_) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Failed to load Razorpay checkout.js'));
    }
  });

  html.document.body?.append(script);
  await completer.future;
}

void initializeRazorpay({
  required void Function(String paymentId) onPaymentSuccess,
  required void Function(String message) onPaymentError,
  required void Function(String walletName) onExternalWallet,
}) {
  _onPaymentSuccess = onPaymentSuccess;
  _onPaymentError = onPaymentError;
  _onExternalWallet = onExternalWallet;
}

Future<void> openRazorpay(Map<String, dynamic> options) async {
  await _ensureCheckoutScriptLoaded();

  final razorpayCtor = js.context['Razorpay'];
  if (razorpayCtor == null) {
    throw StateError('Razorpay SDK unavailable on window');
  }

  final jsOptions = js.JsObject.jsify({
    ...options,
    'handler': (dynamic response) {
      final paymentId = (response['razorpay_payment_id'] as String?) ??
          'web_unknown_payment';
      _onPaymentSuccess?.call(paymentId);
    },
  });

  final instance = js.JsObject(razorpayCtor, [jsOptions]);

  instance.callMethod('on', [
    'payment.failed',
    (dynamic response) {
      try {
        final errorObj = response['error'];
        final description = (errorObj['description'] as String?) ?? 'Payment failed';
        _onPaymentError?.call(description);
      } catch (_) {
        _onPaymentError?.call('Payment failed');
      }
    }
  ]);

  instance.callMethod('on', [
    'external_wallet',
    (dynamic response) {
      final wallet = (response['external_wallet'] as String?) ?? '';
      _onExternalWallet?.call(wallet);
    }
  ]);

  instance.callMethod('open');
}

void disposeRazorpay() {
  _onPaymentSuccess = null;
  _onPaymentError = null;
  _onExternalWallet = null;
}
