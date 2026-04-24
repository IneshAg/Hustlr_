const axios = require('axios');
const { supabase } = require('../config/supabase');

const MAX_ATTEMPTS  = 3;
const RETRY_DELAY   = 30 * 60 * 1000; // 30 min

async function bumpPayoutAttempts(claimId) {
  const { data: row } = await supabase
    .from('claims')
    .select('payout_attempts')
    .eq('id', claimId)
    .maybeSingle();
  const next = (row?.payout_attempts ?? 0) + 1;
  await supabase.from('claims').update({ payout_attempts: next }).eq('id', claimId);
}

/**
 * When USE_REAL_PAYOUT=true and PayPal keys exist, verifies REST credentials.
 * Actual Paypal payout is disabled in sandbox demo; wallet credit still runs on success.
 */
async function paypalCredentialsOk() {
  const id = process.env.PAYPAL_CLIENT_ID;
  const secret = process.env.PAYPAL_CLIENT_SECRET;
  if (!id || !secret) return false;
  try {
    const auth = Buffer.from(`${id}:${secret}`).toString('base64');
    const res = await axios.post('https://api-m.sandbox.paypal.com/v1/oauth2/token', 'grant_type=client_credentials', {
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      timeout: 12000,
      validateStatus: () => true,
    });
    return res.status === 200;
  } catch {
    return false;
  }
}

async function releasePayout({
  claimId,
  userId,
  amount,
  tranche,
  description,
}) {
  await bumpPayoutAttempts(claimId);

  try {
    if (process.env.USE_REAL_PAYOUT === 'true') {
      const gatewayOk = await paypalCredentialsOk();
      if (!gatewayOk) {
        throw new Error('PayPal API verification failed (check keys or network)');
      }
      console.log(
        `[Payout] PayPal sandbox credentials verified — crediting wallet (₹${amount}) claim=${claimId}`
      );
    }

    // Record successful credit
    await supabase
      .from('wallet_transactions')
      .insert([{
        user_id:     userId,
        amount,
        type:        'credit',
        reference:   `${tranche}_${claimId}`,
        description,
      }]);

    console.log(
      `[Payout] ${tranche} released — ` +
      `₹${amount} to user ${userId}`
    );
    return { success: true };

  } catch (e) {
    console.error(`[Payout] Failed:`, e.message);

    // Check retry count
    const { data: claim } = await supabase
      .from('claims')
      .select('payout_attempts')
      .eq('id', claimId)
      .single();

    const attempts = claim?.payout_attempts ?? 0;

    if (attempts < MAX_ATTEMPTS) {
      console.log(
        `[Payout] Scheduling retry ${attempts + 1} ` +
        `of ${MAX_ATTEMPTS} in 30 minutes`
      );
      setTimeout(
        () => releasePayout({ 
          claimId, userId, amount, tranche, description 
        }),
        RETRY_DELAY
      );
    } else {
      // Mark as permanently failed
      await supabase
        .from('claims')
        .update({
          payout_error:     e.message,
          payout_failed_at: new Date().toISOString(),
          status:           'PAYOUT_FAILED',
        })
        .eq('id', claimId);

      console.error(
        `[Payout] PERMANENT FAILURE — claim ${claimId} ` +
        `after ${MAX_ATTEMPTS} attempts`
      );
    }

    return { success: false, error: e.message };
  }
}

module.exports = { releasePayout, paypalCredentialsOk };
