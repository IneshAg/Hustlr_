const express = require('express');
const { supabase } = require('../config/supabase');
const {
  buildClaimPayload,
  buildPolicyPayload,
  buildBillingPayload,
  forwardToGuidewire,
} = require('../services/guidewire-service');

const router = express.Router();

// GET /guidewire/sample-payload/:claimId
router.get('/sample-payload/:claimId', async (req, res) => {
  if (process.env.ENABLE_GUIDEWIRE_ROUTES !== 'true') {
    return res.status(404).json({ error: 'Guidewire routes disabled' });
  }
  try {
    const { claimId } = req.params;
    const { data: claim, error } = await supabase
      .from('claims')
      .select('*')
      .eq('id', claimId)
      .maybeSingle();

    if (error) throw error;
    if (!claim) return res.status(404).json({ error: 'Claim not found' });

    const { data: userRow } = await supabase
      .from('users')
      .select('name, phone, zone')
      .eq('id', claim.user_id)
      .maybeSingle();

    const payload = buildClaimPayload({ ...claim, users: userRow || {} });
    return res.json(payload);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// GET /guidewire/sample-policy/:policyId — PolicyCenter-shaped JSON for demos
router.get('/sample-policy/:policyId', async (req, res) => {
  if (process.env.ENABLE_GUIDEWIRE_ROUTES !== 'true') {
    return res.status(404).json({ error: 'Guidewire routes disabled' });
  }
  try {
    const { policyId } = req.params;
    const { data: policy, error } = await supabase
      .from('policies')
      .select('*')
      .eq('id', policyId)
      .maybeSingle();

    if (error) throw error;
    if (!policy) return res.status(404).json({ error: 'Policy not found' });

    const { data: userRow } = await supabase
      .from('users')
      .select('name, phone, zone, city, iss_score')
      .eq('id', policy.user_id)
      .maybeSingle();

    const payload = buildPolicyPayload(policy, userRow || {});
    return res.json(payload);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// GET /guidewire/sample-billing/:policyId — BillingCenter-shaped JSON
router.get('/sample-billing/:policyId', async (req, res) => {
  if (process.env.ENABLE_GUIDEWIRE_ROUTES !== 'true') {
    return res.status(404).json({ error: 'Guidewire routes disabled' });
  }
  try {
    const { policyId } = req.params;
    const amount = req.query.amount_paise != null
      ? parseInt(String(req.query.amount_paise), 10)
      : null;

    const { data: policy, error } = await supabase
      .from('policies')
      .select('*')
      .eq('id', policyId)
      .maybeSingle();

    if (error) throw error;
    if (!policy) return res.status(404).json({ error: 'Policy not found' });

    const { data: userRow } = await supabase
      .from('users')
      .select('name, phone, zone, city')
      .eq('id', policy.user_id)
      .maybeSingle();

    const payload = buildBillingPayload(policy, userRow || {}, {
      amount_paise: Number.isFinite(amount) ? amount : undefined,
    });
    return res.json(payload);
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// POST /guidewire/forward/:claimId  — optional webhook test
router.post('/forward/:claimId', async (req, res) => {
  if (process.env.ENABLE_GUIDEWIRE_ROUTES !== 'true') {
    return res.status(404).json({ error: 'Guidewire routes disabled' });
  }
  try {
    const { claimId } = req.params;
    const { data: claim, error } = await supabase
      .from('claims')
      .select('*')
      .eq('id', claimId)
      .maybeSingle();

    if (error) throw error;
    if (!claim) return res.status(404).json({ error: 'Claim not found' });

    const { data: userRow } = await supabase
      .from('users')
      .select('name, phone, zone')
      .eq('id', claim.user_id)
      .maybeSingle();

    const payload = buildClaimPayload({ ...claim, users: userRow || {} });
    const forward = await forwardToGuidewire(payload);
    return res.json({ payload, forward });
  } catch (e) {
    return res.status(500).json({ error: e.message });
  }
});

// Simulate Guidewire PolicyCenter webhook
router.post('/policycenter/policy-created', async (req, res) => {
  const { policy_id, confirmation_number } = req.body;
  console.log('[Guidewire] PolicyCenter policy confirmed:', confirmation_number);

  await supabase
    .from('policies')
    .update({ guidewire_policy_number: confirmation_number })
    .eq('id', policy_id);

  return res.json({ received: true });
});

// Simulate Guidewire ClaimCenter webhook
router.post('/claimcenter/claim-routed', async (req, res) => {
  const { claim_id, routing_decision, adjuster_id } = req.body;
  console.log('[Guidewire] ClaimCenter routing:', routing_decision);

  await supabase
    .from('claims')
    .update({
      guidewire_routing: routing_decision,
      adjuster_id:       adjuster_id || null,
    })
    .eq('id', claim_id);

  return res.json({ received: true });
});

// GET /guidewire/sample-payload — for judge testing
router.get('/sample-payload', (req, res) => {
  res.json(require('../../guidewire-marketplace/sample-payloads/claimcenter-claim-create.json'));
});

router.get('/sample-policy', (req, res) => {
  res.json(require('../../guidewire-marketplace/sample-payloads/policycenter-policy-create.json'));
});

router.get('/marketplace-manifest', (req, res) => {
  res.json(require('../../guidewire-marketplace/manifest.json'));
});

module.exports = router;

