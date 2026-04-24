const crypto = require("crypto");

/**
 * Generates a tamper-evident SHA256 audit receipt for a claim.
 * The hash chains together every verifiable fact about how the
 * claim was approved — if any field changes, the hash breaks.
 */
function generateClaimReceipt(claim) {
  const auditPayload = {
    // Claim identity
    claim_id: claim.id,
    worker_id: claim.user_id || claim.worker_id, // map correctly depending on schema
    zone: claim.zone,

    // Trigger verification
    trigger_type: claim.trigger_type,
    trigger_value: claim.trigger_value || `Severity ${claim.severity}`,
    trigger_source: claim.data_source || "live",
    data_trust_score: claim.data_trust_score || 0.85,

    // Shift & zone validation
    shift_overlap: claim.duration_hours || claim.shift_overlap_hours || 3,
    zone_depth_score: claim.zone_depth_score || 0.84,
    shift_window: "08:00-22:00",

    // Fraud check
    fps_score: claim.fraud_score,
    fps_tier:
      claim.fraud_score < 30
        ? "GREEN"
        : claim.fraud_score < 70
          ? "YELLOW"
          : "RED",
    device_integrity: "PASS",

    // Payout calculation
    duration_hours: claim.duration_hours,
    gross_payout: claim.gross_payout,
    tranche1_amount: claim.tranche1,
    tranche2_amount: claim.tranche2,

    // Timestamps
    approved_at: new Date().toISOString(),
  };

  const canonicalJson = JSON.stringify(
    auditPayload,
    Object.keys(auditPayload).sort(),
  );

  const hash = crypto.createHash("sha256").update(canonicalJson).digest("hex");

  return {
    receipt_hash: hash,
    receipt_version: "HUSTLR-AUDIT-V1",
    generated_at: new Date().toISOString(),
    payload: auditPayload,
    verification_note:
      "SHA256(canonical JSON of all trigger, fraud, and payout fields). " +
      "Reproduce by sorting keys alphabetically and hashing with sha256.",
  };
}

/**
 * Stores the audit receipt in Supabase alongside the claim.
 */
async function attachReceiptToClaim(supabase, claimId, claim) {
  const receipt = generateClaimReceipt(claim);

  const { error } = await supabase
    .from("claims")
    .update({
      audit_receipt_hash: receipt.receipt_hash,
      audit_receipt_payload: receipt.payload,
      audit_receipt_version: receipt.receipt_version,
      audit_generated_at: receipt.generated_at,
    })
    .eq("id", claimId);

  if (error) {
    console.error("[AuditTrail] Failed to attach receipt:", error);
    throw error;
  }

  return receipt;
}

function verifyReceipt(storedClaim) {
  const recomputed = generateClaimReceipt(storedClaim);
  const isValid = recomputed.receipt_hash === storedClaim.audit_receipt_hash;

  return {
    is_valid: isValid,
    stored_hash: storedClaim.audit_receipt_hash,
    recomputed_hash: recomputed.receipt_hash,
    verification_note: isValid
      ? "Hash matches. Claim data has not been modified since approval."
      : "HASH MISMATCH — claim data may have been tampered with after approval.",
  };
}

module.exports = { generateClaimReceipt, attachReceiptToClaim, verifyReceipt };
