const express = require('express');
const { supabase } = require('../config/supabase');
const {
  startSingleSession,
  revokeSessionByToken,
} = require('../services/session-service');
const { requireSession } = require('../middleware/session-auth');

const router = express.Router();

router.post('/send-otp', async (req, res) => {
  try {
    const { phone } = req.body;
    const { error } = await supabase.auth.signInWithOtp({ phone });
    if (error) throw error;
    res.json({ message: 'OTP sent', phone });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/verify-otp', async (req, res) => {
  try {
    const { phone, token } = req.body;
    const { data, error } = await supabase.auth.verifyOtp({
      phone,
      token,
      type: 'sms',
    });
    if (error) throw error;
    res.json({ access_token: data.session?.access_token, user: data.user });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

router.post('/session/login', async (req, res) => {
  try {
    const userIdInput =
      typeof req.body?.user_id === 'string' ? req.body.user_id.trim() : '';
    const phoneInput =
      typeof req.body?.phone === 'string' ? req.body.phone.trim() : '';
    const deviceId =
      typeof req.body?.device_id === 'string' && req.body.device_id.trim()
        ? req.body.device_id.trim()
        : null;
    const deviceLabel =
      typeof req.body?.device_label === 'string' && req.body.device_label.trim()
        ? req.body.device_label.trim()
        : null;

    if (!userIdInput && !phoneInput) {
      return res.status(400).json({ error: 'user_id or phone is required' });
    }

    let user = null;
    if (userIdInput) {
      const { data, error } = await supabase
        .from('users')
        .select('id, phone')
        .eq('id', userIdInput)
        .maybeSingle();
      if (error) throw error;
      user = data;
    } else {
      const { data, error } = await supabase
        .from('users')
        .select('id, phone')
        .eq('phone', phoneInput)
        .maybeSingle();
      if (error) throw error;
      user = data;
    }

    if (!user) return res.status(404).json({ error: 'User not found' });

    const out = await startSingleSession({
      userId: user.id,
      phone: user.phone,
      deviceId,
      deviceLabel,
    });

    return res.json({
      user_id: user.id,
      phone: user.phone,
      session_token: out.session_token,
      session: out.session,
      revoked_sessions: out.revoked_sessions,
    });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
});

router.post('/session/logout', requireSession, async (req, res) => {
  try {
    const out = await revokeSessionByToken(req.sessionToken, 'logout');
    return res.json({ ok: true, revoked: out.revoked });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
});

router.get('/session/me', requireSession, async (req, res) => {
  return res.json({ session: req.session });
});

module.exports = router;


