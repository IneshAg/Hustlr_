const express = require('express');
const crypto = require('crypto');
const { supabase } = require('../config/supabase');
const router = express.Router();

// GET /wallet/:userId
router.get('/:user_id', async (req, res) => {
  const { user_id } = req.params;

  try {
    const { data: txns, error } = await supabase
      .from('wallet_transactions')
      .select('*')
      .eq('user_id', user_id)
      .order('created_at', { ascending: false })
      .limit(20);

    if (error) throw error;

    const credits = txns.filter(t => t.type === 'credit');
    const debits  = txns.filter(t => t.type === 'debit');

    const total_payouts  = credits.reduce((s, t) => s + t.amount, 0);
    const total_premiums = debits.reduce((s, t)  => s + t.amount, 0);
    const balance        = total_payouts - total_premiums;

    return res.json({
      balance,
      total_payouts,
      total_premiums,
      transactions: txns,
    });

  } catch (e) {
    console.error('[Wallet] Get error:', e.message);
    return res.status(500).json({ error: e.message });
  }
});

// GET /wallet/cashback-status/:userId
router.get('/cashback-status/:user_id', async (req, res) => {
  const { user_id } = req.params;
  try {
    const { data: policy } = await supabase
      .from('policies')
      .select('*')
      .eq('user_id', user_id)
      .eq('status', 'active')
      .maybeSingle();
      
    // Mocking 15% cashback cron logic for the app.
    // If they have an active policy, simulate an in-progress quarter.
    if (policy) {
      return res.json({
         current_clean_weeks: 11,
         quarter_start: new Date(Date.now() - 11 * 7 * 24 * 60 * 60 * 1000).toISOString(),
         potential_cashback: (policy.weekly_premium || 49) * 13 * 0.15,
         status: 'in_progress'
      });
    }

    return res.json({
       current_clean_weeks: 0,
       quarter_start: new Date().toISOString(),
       potential_cashback: 0.0,
       status: 'reset'
    });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// POST /wallet/credit
router.post('/credit', async (req, res) => {
  const { user_id, amount, description, reference, idempotency_key } = req.body;
  try {
    const minuteWindow = new Date().toISOString().slice(0, 16);
    const key = idempotency_key || crypto.createHash('sha256').update(`credit-${user_id}-${amount}-${minuteWindow}`).digest('hex');

    const { data: transaction, error } = await supabase
      .from('wallet_transactions')
      .insert([{ user_id, amount: Math.abs(amount), type: 'credit', description, reference, idempotency_key: key }])
      .select()
      .single();
    if (error) throw error;
    res.json({ transaction });
  } catch (e) {
    if (e.code === '23505') {
      return res.status(409).json({ error: 'Duplicate transaction detected.' });
    }
    res.status(500).json({ error: e.message });
  }
});

// POST /wallet/debit
router.post('/debit', async (req, res) => {
  const { user_id, amount, description, reference, idempotency_key } = req.body;
  try {
    const minuteWindow = new Date().toISOString().slice(0, 16);
    const key = idempotency_key || crypto.createHash('sha256').update(`debit-${user_id}-${amount}-${minuteWindow}`).digest('hex');

    const { data: transaction, error } = await supabase
      .from('wallet_transactions')
      .insert([{ user_id, amount: Math.abs(amount), type: 'debit', description, reference, idempotency_key: key }])
      .select()
      .single();
    if (error) throw error;
    res.json({ transaction });
  } catch (e) {
    if (e.code === '23505') {
      return res.status(409).json({ error: 'Duplicate transaction detected.' });
    }
    res.status(500).json({ error: e.message });
  }
});

// POST /wallet/initiate-upi
// POST /wallet/withdraw - Unified endpoint for UPI and Bank withdrawals
router.post('/withdraw', async (req, res) => {
  const { user_id, amount, destination, upi_id } = req.body;
  
  if (!user_id || !amount) {
    return res.status(400).json({ error: 'Missing required parameters' });
  }
  
  try {
    // 1. Check current balance
    const { data: txns, error: balanceError } = await supabase
      .from('wallet_transactions')
      .select('amount, type')
      .eq('user_id', user_id);
      
    if (balanceError) throw balanceError;
    
    const balance = (txns || []).reduce((acc, t) => 
      t.type === 'credit' ? acc + t.amount : acc - t.amount, 0);
      
    if (balance < amount) {
      return res.status(400).json({ error: 'Insufficient balance' });
    }

    // 2. Idempotency to prevent double-withdrawals within the same minute
    const minuteWindow = new Date().toISOString().slice(0, 16); 
    const idempotencyKey = crypto.createHash('sha256')
      .update(`withdraw-${user_id}-${amount}-${destination}-${minuteWindow}`)
      .digest('hex');

    // 3. Record the withdrawal
    const { data: txn, error } = await supabase.from('wallet_transactions').insert({
      user_id, 
      amount: Math.abs(amount), 
      type: 'debit', 
      category: 'withdrawal',
      description: `Withdrawal to ${destination.toUpperCase()}${upi_id ? ' (' + upi_id + ')' : ''}`,
      upi_ref: upi_id,
      metadata: { destination, upi_id },
      idempotency_key: idempotencyKey
    }).select().single();
    
    if (error) {
      if (error.code === '23505') {
        return res.status(409).json({ error: 'Duplicate withdrawal detected. Please wait a minute.' });
      }
      throw error;
    }
    
    res.json({ 
      status: 'success',
      message: 'Withdrawal processed', 
      transaction_id: txn.id,
      amount,
      destination 
    });
  } catch (e) {
    console.error('[Wallet] Withdraw error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
