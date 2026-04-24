'use strict';

const crypto = require('crypto');
const { supabase } = require('../config/supabase');

function _hashSessionToken(sessionToken) {
  return crypto.createHash('sha256').update(sessionToken).digest('hex');
}

function _generateSessionToken() {
  return crypto.randomBytes(48).toString('base64url');
}

async function startSingleSession({
  userId,
  phone,
  deviceId = null,
  deviceLabel = null,
}) {
  if (!userId || !phone) {
    throw new Error('userId and phone are required');
  }

  const now = new Date().toISOString();
  const sessionToken = _generateSessionToken();
  const tokenHash = _hashSessionToken(sessionToken);

  const { data: revokedRows, error: revokeError } = await supabase
    .from('auth_sessions')
    .update({
      is_active: false,
      revoked_at: now,
      revoked_reason: 'new_login',
    })
    .eq('user_id', userId)
    .eq('is_active', true)
    .select('id');

  if (revokeError) throw revokeError;

  const { data: sessionRow, error: insertError } = await supabase
    .from('auth_sessions')
    .insert({
      user_id: userId,
      phone,
      token_hash: tokenHash,
      device_id: deviceId,
      device_label: deviceLabel,
      is_active: true,
      created_at: now,
      last_seen_at: now,
    })
    .select('id, user_id, phone, device_id, device_label, created_at, last_seen_at')
    .single();

  if (insertError) throw insertError;

  return {
    session_token: sessionToken,
    session: sessionRow,
    revoked_sessions: (revokedRows || []).length,
  };
}

async function getActiveSessionByToken(sessionToken) {
  if (!sessionToken || typeof sessionToken !== 'string') return null;

  const tokenHash = _hashSessionToken(sessionToken.trim());
  const { data: session, error } = await supabase
    .from('auth_sessions')
    .select('id, user_id, phone, device_id, device_label, created_at, last_seen_at')
    .eq('token_hash', tokenHash)
    .eq('is_active', true)
    .maybeSingle();

  if (error) throw error;
  if (!session) return null;

  const lastSeenMs = session.last_seen_at
    ? new Date(session.last_seen_at).getTime()
    : 0;
  if (Number.isFinite(lastSeenMs) && Date.now() - lastSeenMs > 60 * 1000) {
    await supabase
      .from('auth_sessions')
      .update({ last_seen_at: new Date().toISOString() })
      .eq('id', session.id);
  }

  return session;
}

async function revokeSessionByToken(sessionToken, reason = 'logout') {
  if (!sessionToken || typeof sessionToken !== 'string') {
    return { ok: true, revoked: 0 };
  }

  const tokenHash = _hashSessionToken(sessionToken.trim());
  const { data, error } = await supabase
    .from('auth_sessions')
    .update({
      is_active: false,
      revoked_at: new Date().toISOString(),
      revoked_reason: reason,
    })
    .eq('token_hash', tokenHash)
    .eq('is_active', true)
    .select('id');

  if (error) throw error;
  return { ok: true, revoked: (data || []).length };
}

module.exports = {
  startSingleSession,
  getActiveSessionByToken,
  revokeSessionByToken,
};
