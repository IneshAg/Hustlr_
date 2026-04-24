'use strict';

const { getActiveSessionByToken } = require('../services/session-service');

function extractSessionToken(req) {
  const authHeader = req.headers.authorization || req.headers.Authorization;
  if (typeof authHeader === 'string') {
    const [scheme, value] = authHeader.split(' ');
    if (scheme?.toLowerCase() === 'bearer' && value) {
      return value.trim();
    }
  }

  const headerToken =
    req.headers['x-session-token'] || req.headers['x-auth-session'];
  if (typeof headerToken === 'string' && headerToken.trim()) {
    return headerToken.trim();
  }

  return null;
}

async function requireSession(req, res, next) {
  try {
    const token = extractSessionToken(req);
    if (!token) {
      return res.status(401).json({ error: 'Authentication required' });
    }

    const session = await getActiveSessionByToken(token);
    if (!session) {
      return res
        .status(401)
        .json({ error: 'Session expired. Please log in again.' });
    }

    req.sessionToken = token;
    req.session = session;
    req.authUserId = session.user_id;
    return next();
  } catch (e) {
    return res.status(401).json({ error: e.message || 'Invalid session' });
  }
}

module.exports = {
  requireSession,
  extractSessionToken,
};

