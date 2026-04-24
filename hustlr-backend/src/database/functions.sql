-- Database Functions for Critical Business Logic
-- These functions handle atomic operations and complex business rules

-- Process Claim Payout (Atomic Transaction)
CREATE OR REPLACE FUNCTION process_claim_payout(
  p_claim_id UUID,
  p_payment_method TEXT,
  p_upi_ref TEXT DEFAULT NULL
)
RETURNS TABLE(success BOOLEAN, message TEXT, payout_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  claim_record RECORD;
  payout_id UUID;
  tranche1_id UUID;
  tranche2_id UUID;
BEGIN
  -- Get claim details and lock row
  SELECT * INTO claim_record 
  FROM claims 
  WHERE id = p_claim_id AND status = 'APPROVED'
  FOR UPDATE;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'Claim not found or not approved', NULL::UUID;
    RETURN;
  END IF;
  
  -- Check if already paid
  IF claim_record.settled_at IS NOT NULL THEN
    RETURN QUERY SELECT FALSE, 'Claim already paid out', NULL::UUID;
    RETURN;
  END IF;
  
  -- Generate unique payout ID
  payout_id := gen_random_uuid();
  
  -- Process tranche 1 (70% of payout)
  tranche1_id := gen_random_uuid();
  INSERT INTO wallet_transactions (
    id, user_id, amount, type, category, description, claim_id, upi_ref, idempotency_key
  ) VALUES (
    tranche1_id, 
    claim_record.user_id, 
    claim_record.tranche1, 
    'credit', 
    'payout_tranche1', 
    'Claim payout - Tranche 1', 
    p_claim_id, 
    p_upi_ref, 
    'payout_' || payout_id || '_tranche1'
  );
  
  -- Process tranche 2 (30% of payout)
  tranche2_id := gen_random_uuid();
  INSERT INTO wallet_transactions (
    id, user_id, amount, type, category, description, claim_id, upi_ref, idempotency_key
  ) VALUES (
    tranche2_id, 
    claim_record.user_id, 
    claim_record.tranche2, 
    'credit', 
    'payout_tranche2', 
    'Claim payout - Tranche 2', 
    p_claim_id, 
    p_upi_ref, 
    'payout_' || payout_id || '_tranche2'
  );
  
  -- Update claim status
  UPDATE claims 
  SET 
    status = 'SETTLED',
    settled_at = NOW(),
    tranche1_released_at = NOW(),
    tranche2_released_at = NOW(),
    payout_attempts = payout_attempts + 1
  WHERE id = p_claim_id;
  
  -- Update balance snapshot
  INSERT INTO wallet_balance_snapshots (user_id, balance, calculated_at)
  SELECT 
    user_id, 
    (SELECT COALESCE(SUM(amount), 0) FROM wallet_transactions WHERE user_id = claim_record.user_id),
    NOW()
  ON CONFLICT (user_id, calculated_at) DO UPDATE SET
    balance = EXCLUDED.balance;
  
  RETURN QUERY SELECT TRUE, 'Payout processed successfully', payout_id;
END;
$$;

-- Calculate Gross Payout with Compound Multipliers
CREATE OR REPLACE FUNCTION calculate_gross_payout(
  p_policy_id UUID,
  p_severity FLOAT,
  p_duration_hours FLOAT,
  p_zone TEXT,
  p_trigger_type TEXT
)
RETURNS TABLE(base_payout INTEGER, compound_multiplier FLOAT, gross_payout INTEGER) LANGUAGE plpgsql AS $$
DECLARE
  policy_record RECORD;
  multiplier FLOAT := 1.0;
  zone_depth_score FLOAT := 0.0;
BEGIN
  -- Get policy details
  SELECT * INTO policy_record 
  FROM policies 
  WHERE id = p_policy_id;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT 0, 1.0, 0;
    RETURN;
  END IF;
  
  -- Calculate zone depth score
  SELECT calculate_zone_depth_score(p_zone, NULL, NULL) INTO zone_depth_score;
  
  -- Calculate compound multiplier
  multiplier := calculate_compound_multiplier(policy_record.plan_tier, p_severity);
  
  -- Apply zone depth multiplier
  multiplier := multiplier * (0.8 + (zone_depth_score * 0.4));
  
  -- Calculate base payout (severity * duration * base rate)
  base_payout := FLOOR(p_severity * p_duration_hours * 100);
  
  -- Apply compound multiplier
  gross_payout := FLOOR(base_payout * multiplier);
  
  -- Cap at policy maximum
  gross_payout := LEAST(gross_payout, policy_record.max_weekly_payout);
  
  RETURN QUERY SELECT base_payout, multiplier, gross_payout;
END;
$$;

-- Process Premium Deduction (Atomic)
CREATE OR REPLACE FUNCTION process_premium_deduction(
  p_user_id UUID,
  p_policy_id UUID,
  p_amount INTEGER,
  p_payment_method TEXT DEFAULT 'wallet'
)
RETURNS TABLE(success BOOLEAN, message TEXT, transaction_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  transaction_id UUID;
  user_balance INTEGER;
BEGIN
  -- Get current user balance
  SELECT COALESCE(SUM(amount), 0) INTO user_balance
  FROM wallet_transactions 
  WHERE user_id = p_user_id;
  
  -- Check sufficient balance
  IF user_balance < p_amount THEN
    RETURN QUERY SELECT FALSE, 'Insufficient balance', NULL::UUID;
    RETURN;
  END IF;
  
  -- Generate transaction ID
  transaction_id := gen_random_uuid();
  
  -- Process premium deduction
  INSERT INTO wallet_transactions (
    id, user_id, amount, type, category, description, policy_id, idempotency_key
  ) VALUES (
    transaction_id,
    p_user_id,
    p_amount,
    'debit',
    'premium',
    'Weekly premium deduction',
    p_policy_id,
    'premium_' || p_policy_id || '_' || EXTRACT(EPOCH FROM NOW())
  );
  
  -- Update policy paid_until date
  UPDATE policies 
  SET paid_until = paid_until + INTERVAL '7 days'
  WHERE id = p_policy_id;
  
  -- Update balance snapshot
  INSERT INTO wallet_balance_snapshots (user_id, balance, calculated_at)
  SELECT 
    p_user_id, 
    (SELECT COALESCE(SUM(amount), 0) FROM wallet_transactions WHERE user_id = p_user_id),
    NOW()
  ON CONFLICT (user_id, calculated_at) DO UPDATE SET
    balance = EXCLUDED.balance;
  
  RETURN QUERY SELECT TRUE, 'Premium processed successfully', transaction_id;
END;
$$;

-- Process Cashback Payout (Quarterly)
CREATE OR REPLACE FUNCTION process_cashback_payout(
  p_user_id UUID,
  p_period_start DATE,
  p_period_end DATE
)
RETURNS TABLE(success BOOLEAN, cashback_amount INTEGER, payout_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  cashback INTEGER;
  payout_id UUID;
  existing_payout RECORD;
BEGIN
  -- Check if cashback already processed for this period
  SELECT * INTO existing_payout
  FROM cashback_payouts
  WHERE user_id = p_user_id 
    AND period_start = p_period_start 
    AND period_end = p_period_end 
    AND status = 'paid';
  
  IF FOUND THEN
    RETURN QUERY SELECT FALSE, 0, existing_payout.id;
    RETURN;
  END IF;
  
  -- Calculate cashback
  cashback := calculate_cashback(p_user_id, p_period_start, p_period_end);
  
  IF cashback <= 0 THEN
    RETURN QUERY SELECT FALSE, 0, NULL::UUID;
    RETURN;
  END IF;
  
  -- Generate payout ID
  payout_id := gen_random_uuid();
  
  -- Process cashback payout
  INSERT INTO cashback_payouts (
    id, user_id, amount, period_start, period_end, status, paid_at
  ) VALUES (
    payout_id, p_user_id, cashback, p_period_start, p_period_end, 'paid', NOW()
  );
  
  -- Add to wallet
  INSERT INTO wallet_transactions (
    user_id, amount, type, category, description, idempotency_key
  ) VALUES (
    p_user_id, 
    cashback, 
    'credit', 
    'cashback', 
    'Quarterly cashback payout', 
    'cashback_' || payout_id
  );
  
  -- Update user cashback earned
  UPDATE users 
  SET cashback_earned = cashback_earned + cashback,
      cashback_pending = 0
  WHERE id = p_user_id;
  
  RETURN QUERY SELECT TRUE, cashback, payout_id;
END;
$$;

-- Update Trust Score with Event Logging
CREATE OR REPLACE FUNCTION update_trust_score_with_event(
  p_user_id UUID,
  p_event_type TEXT,
  p_score_change INTEGER,
  p_reason TEXT DEFAULT NULL
)
RETURNS TABLE(new_score INTEGER, trust_tier TEXT) LANGUAGE plpgsql AS $$
DECLARE
  old_score INTEGER;
  new_score INTEGER;
  new_tier TEXT;
BEGIN
  -- Get current score
  SELECT trust_score INTO old_score
  FROM users 
  WHERE id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT 0, 'AT_RISK';
    RETURN;
  END IF;
  
  -- Calculate new score
  new_score := GREATEST(LEAST(old_score + p_score_change, 1000), 0);
  
  -- Determine new tier
  new_tier := CASE 
    WHEN new_score >= 900 THEN 'PLATINUM'
    WHEN new_score >= 750 THEN 'GOLD'
    WHEN new_score >= 600 THEN 'SILVER'
    WHEN new_score >= 500 THEN 'BRONZE'
    ELSE 'AT_RISK'
  END;
  
  -- Update user
  UPDATE users 
  SET trust_score = new_score, trust_tier = new_tier
  WHERE id = p_user_id;
  
  -- Log event
  INSERT INTO trust_events (user_id, event_type, score_change, new_score, reason)
  VALUES (p_user_id, p_event_type, p_score_change, new_score, p_reason);
  
  RETURN QUERY SELECT new_score, new_tier;
END;
$$;

-- Process Shift Gap Detection and Penalties
CREATE OR REPLACE FUNCTION process_shift_gap_detection(
  p_worker_id UUID,
  p_gap_start TIMESTAMPTZ,
  p_gap_end TIMESTAMPTZ
)
RETURNS TABLE(gap_id UUID, penalty_applied INTEGER) LANGUAGE plpgsql AS $$
DECLARE
  gap_duration_seconds INTEGER;
  penalty INTEGER := 0;
  gap_id UUID;
BEGIN
  -- Calculate gap duration
  gap_duration_seconds := EXTRACT(EPOCH FROM (p_gap_end - p_gap_start))::INTEGER;
  
  -- Calculate penalty based on duration
  penalty := CASE 
    WHEN gap_duration_seconds > 3600 THEN 30  -- 1+ hour
    WHEN gap_duration_seconds > 1800 THEN 20  -- 30+ min
    WHEN gap_duration_seconds > 600 THEN 10   -- 10+ min
    ELSE 0
  END;
  
  -- Generate gap ID
  gap_id := gen_random_uuid();
  
  -- Create shift gap record
  INSERT INTO shift_gaps (
    id, worker_id, gap_start, gap_end, gap_duration_seconds, frs_penalty
  ) VALUES (
    gap_id, p_worker_id, p_gap_start, p_gap_end, gap_duration_seconds, penalty
  );
  
  -- Apply penalty if any
  IF penalty > 0 THEN
    PERFORM update_trust_score_with_event(
      p_worker_id, 
      'shift_gap_penalty', 
      -penalty, 
      'Shift gap: ' || gap_duration_seconds || ' seconds'
    );
  END IF;
  
  RETURN QUERY SELECT gap_id, penalty;
END;
$$;

-- Generate Work Advisor Nudges
CREATE OR REPLACE FUNCTION generate_work_advisor_nudges(
  p_zone TEXT,
  p_plan_tier TEXT
)
RETURNS TABLE(recommendation TEXT, confidence_score FLOAT, nudge_id UUID) LANGUAGE plpgsql AS $$
DECLARE
  nudge_id UUID;
BEGIN
  -- Generate nudge ID
  nudge_id := gen_random_uuid();
  
  -- Generate recommendations based on zone and tier
  INSERT INTO work_advisor_logs (
    id, zone, plan_tier, recommendation, confidence_score
  )
  SELECT 
    recommendation, 
    confidence_score, 
    nudge_id
  FROM generate_work_advice(p_zone, p_plan_tier::plan_tier_enum);
  
  RETURN QUERY 
  SELECT recommendation, confidence_score, nudge_id
  FROM work_advisor_logs 
  WHERE id = nudge_id;
END;
$$;

-- Check and Trigger Circuit Breaker
CREATE OR REPLACE FUNCTION check_and_trigger_circuit_breaker(
  p_zone TEXT,
  p_trigger_type TEXT
)
RETURNS TABLE(is_blocked BOOLEAN, breaker_id UUID, reset_time TIMESTAMPTZ) LANGUAGE plpgsql AS $$
DECLARE
  breaker_id UUID;
  reset_time TIMESTAMPTZ;
  is_blocked BOOLEAN := FALSE;
BEGIN
  -- Check if circuit breaker should trigger
  is_blocked := NOT check_circuit_breaker(p_zone, p_trigger_type);
  
  -- Get circuit breaker details if triggered
  IF is_blocked THEN
    SELECT id, reset_at INTO breaker_id, reset_time
    FROM circuit_breakers 
    WHERE zone = p_zone AND trigger_type = p_trigger_type AND tripped = TRUE;
  END IF;
  
  RETURN QUERY SELECT is_blocked, breaker_id, reset_time;
END;
$$;

-- Process Weekly Settlement
CREATE OR REPLACE FUNCTION process_weekly_settlement(
  p_week_start DATE,
  p_city TEXT,
  p_risk_type TEXT DEFAULT 'rain'
)
RETURNS TABLE(settlement_id UUID, total_premium INTEGER, total_claims INTEGER, loss_ratio FLOAT) LANGUAGE plpgsql AS $$
DECLARE
  settlement_id UUID;
  total_premium INTEGER := 0;
  total_claims INTEGER := 0;
  loss_ratio FLOAT := 0;
  policies_count INTEGER := 0;
  claims_count INTEGER := 0;
BEGIN
  -- Generate settlement ID
  settlement_id := gen_random_uuid();
  
  -- Calculate totals for the week
  SELECT 
    COALESCE(SUM(weekly_premium), 0),
    COALESCE(SUM(gross_payout), 0)
  INTO total_premium, total_claims
  FROM policies p
  LEFT JOIN claims c ON p.id = c.policy_id 
    AND c.status = 'SETTLED'
    AND c.created_at >= p_week_start
    AND c.created_at < p_week_start + INTERVAL '7 days'
  WHERE p.city = p_city 
    AND p.status = 'active';
  
  -- Calculate loss ratio
  loss_ratio := CASE 
    WHEN total_premium > 0 THEN (total_claims::FLOAT / total_premium::FLOAT)
    ELSE 0
  END;
  
  -- Get counts
  SELECT COUNT(*) INTO policies_count
  FROM policies 
  WHERE city = p_city AND status = 'active';
  
  SELECT COUNT(*) INTO claims_count
  FROM claims 
  WHERE city = p_city 
    AND status = 'SETTLED'
    AND created_at >= p_week_start
    AND created_at < p_week_start + INTERVAL '7 days';
  
  -- Create settlement record
  INSERT INTO weekly_settlements (
    id, week_start, week_end, city, risk_type, 
    total_premium, total_claims_paid, loss_ratio,
    policies_count, claims_count, settled_at
  ) VALUES (
    settlement_id, p_week_start, p_week_start + INTERVAL '6 days',
    p_city, p_risk_type, total_premium, total_claims, loss_ratio,
    policies_count, claims_count, NOW()
  );
  
  -- Update pool health
  INSERT INTO pool_health (
    week_start, city, risk_type, premiums_collected, 
    claims_paid, loss_ratio, enrollment_stopped
  ) VALUES (
    p_week_start, p_city, p_risk_type, total_premium, 
    total_claims, loss_ratio, loss_ratio > 0.4
  )
  ON CONFLICT (week_start, city, risk_type) DO UPDATE SET
    premiums_collected = EXCLUDED.premiums_collected,
    claims_paid = EXCLUDED.claims_paid,
    loss_ratio = EXCLUDED.loss_ratio,
    enrollment_stopped = EXCLUDED.enrollment_stopped;
  
  RETURN QUERY SELECT settlement_id, total_premium, total_claims, loss_ratio;
END;
$$;
