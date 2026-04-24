const express = require('express');
const {
  issueNonce,
  verifyIntegrityToken,
  isConfigured,
  isSimulatedMode,
} = require('../services/play-integrity-service');

const router = express.Router();

const defaultPackage = () =>
  process.env.PLAY_INTEGRITY_PACKAGE_NAME || 'com.shieldgig.shieldgig';

/**
 * GET /integrity/play/nonce — server-issued nonce for Play Integrity token request.
 */
router.get('/play/nonce', (req, res) => {
  const out = issueNonce();
  res.json({
    ok: true,
    ...out,
    package_name: defaultPackage(),
    play_integrity_configured: isConfigured(),
    play_integrity_simulated: isSimulatedMode(),
  });
});

/**
 * POST /integrity/play/verify
 * Body: { integrity_token | token, package_name? }
 *
 * - PLAY_INTEGRITY_BYPASS_DEV=true → accepts any non-empty token (local dev).
 * - Else uses service account + Google decodeIntegrityToken (needs Play Console link + API enabled).
 * - PLAY_INTEGRITY_SIMULATED=true → mock verdict JSON (no Google); for judge demos without billing.
 * - Body simulate_integrity_fail=true → mock failing device (for fraud +30 demo).
 * - PLAY_INTEGRITY_SKIP_NONCE_CHECK=true → do not require prior GET /play/nonce (less secure).
 */
router.post('/play/verify', async (req, res) => {
  const token = req.body?.integrity_token || req.body?.token || '';
  const packageName = req.body?.package_name || defaultPackage();

  if (!token || typeof token !== 'string') {
    return res.status(400).json({
      ok: false,
      play_integrity_pass: false,
      reason: 'missing_integrity_token',
      detail: 'Request a token on-device, then POST it here.',
    });
  }

  const bypass = process.env.PLAY_INTEGRITY_BYPASS_DEV === 'true';
  if (bypass) {
    return res.json({
      ok: true,
      play_integrity_pass: true,
      mode: 'dev_bypass',
      package_name: packageName,
      note: 'PLAY_INTEGRITY_BYPASS_DEV=true — disable in production.',
    });
  }

  if (isSimulatedMode()) {
    try {
      const result = await verifyIntegrityToken(token, packageName, {
        skipNonce: true,
        simulateFail: req.body?.simulate_integrity_fail === true,
      });
      return res.json({
        ok: result.ok,
        play_integrity_pass: result.play_integrity_pass,
        mode: result.mode,
        evaluated: result.evaluated,
        mock_verdict: result.mock_verdict,
        judge_note: result.judge_note,
        package_name: packageName,
        nonce_valid: result.nonce_valid,
        verdict: result.verdict,
        summary: result.summary,
      });
    } catch (e) {
      return res.status(502).json({
        ok: false,
        play_integrity_pass: false,
        mode: 'simulated_error',
        reason: e.message,
      });
    }
  }

  if (!isConfigured()) {
    return res.status(503).json({
      ok: false,
      play_integrity_pass: false,
      mode: 'server_not_configured',
      detail:
        'Set play-integrity-service_ACCOUNT_JSON (Render) or GOOGLE_APPLICATION_CREDENTIALS (path to JSON). Or use PLAY_INTEGRITY_SIMULATED=true for a mock verdict (demo only).',
    });
  }

  try {
    const skipNonce = process.env.PLAY_INTEGRITY_SKIP_NONCE_CHECK === 'true';
    const result = await verifyIntegrityToken(token, packageName, { skipNonce });
    return res.json({
      ok: result.ok,
      play_integrity_pass: result.play_integrity_pass,
      mode: result.mode || 'google_decode',
      package_name: packageName,
      nonce_valid: result.nonce_valid,
      verdict: result.verdict,
      summary: result.summary,
    });
  } catch (e) {
    const status = e.code === 'google_api_error' && e.status === 404 ? 400 : 502;
    return res.status(status).json({
      ok: false,
      play_integrity_pass: false,
      mode: 'verify_error',
      reason: e.message,
      details: e.details || undefined,
    });
  }
});

module.exports = router;

