const express = require('express');

const router = express.Router();

function providerCapabilities() {
  return {
    paypal: {
      available: true,
      mode: process.env.PAYPAL_CLIENT_ID && process.env.PAYPAL_CLIENT_SECRET ? 'sandbox_keys_present' : 'mock_sandbox',
      publishable_key_present: !!process.env.PAYPAL_CLIENT_ID,
      recommended: true,
      sandbox_url: 'https://sandbox.paypal.com',
    },
    stripe: {
      available: true,
      mode: process.env.STRIPE_PUBLISHABLE_KEY ? 'sandbox_keys_present' : 'mock_sandbox',
      publishable_key_present: !!process.env.STRIPE_PUBLISHABLE_KEY,
      recommended: false,
    },
    razorpay: {
      available: !!process.env.RAZORPAY_KEY_ID,
      mode: process.env.RAZORPAY_KEY_ID ? 'sandbox_keys_present' : 'not_configured',
      publishable_key_present: !!process.env.RAZORPAY_KEY_ID,
      recommended: false,
    },
    wallet: {
      available: true,
      mode: 'internal_wallet',
      publishable_key_present: false,
      recommended: false,
    },
  };
}

router.get('/sandbox/config', async (_req, res) => {
  res.json({
    default_provider: 'paypal',
    currency: 'INR',
    providers: providerCapabilities(),
  });
});

router.post('/sandbox/session', async (req, res) => {
  try {
    const {
      provider = 'stripe',
      amount = 0,
      currency = 'INR',
      description = 'Hustlr coverage purchase',
      user_id = null,
      metadata = {},
    } = req.body || {};

    const capabilities = providerCapabilities();
    const selected = capabilities[provider] || capabilities.stripe;
    const session_id = `sandbox_${provider}_${Date.now()}`;

    res.json({
      session_id,
      provider,
      currency,
      amount,
      description,
      status: 'pending_confirmation',
      mode: selected.mode,
      hosted_checkout_url: null,
      user_id,
      metadata,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.post('/sandbox/confirm', async (req, res) => {
  try {
    const {
      session_id,
      provider = 'stripe',
      amount = 0,
      currency = 'INR',
      user_id = null,
      metadata = {},
    } = req.body || {};

    res.json({
      success: true,
      payment: {
        id: `pay_${Date.now()}`,
        session_id: session_id || `sandbox_${provider}_${Date.now()}`,
        provider,
        status: 'paid',
        amount,
        currency,
        user_id,
        metadata,
        receipt_url: null,
        confirmed_at: new Date().toISOString(),
      },
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
