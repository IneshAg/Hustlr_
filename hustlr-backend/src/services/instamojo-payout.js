const { v4: uuidv4 } = require('uuid');

const INSTAMOJO_API_KEY = process.env.INSTAMOJO_API_KEY;
const INSTAMOJO_AUTH_TOKEN = process.env.INSTAMOJO_AUTH_TOKEN;

async function initiateUpiPayout(workerUpi, amountPaise, purpose = "payout", referenceId = null) {
  if (!referenceId) {
    referenceId = `HUSTLR-${uuidv4().substring(0, 8).toUpperCase()}`;
  }

  try {
    // 🔥 Since Instamojo does NOT support payouts,
    // we simulate a realistic payout response

    const amountInr = Math.floor(amountPaise / 100);

    console.log(`Instamojo (SIMULATED): payout | upi=${workerUpi} | amount=₹${amountInr}`);

    return {
      source: "instamojo_simulated",
      status: "processed", // can be: processing / success / failed
      payout_id: `imo_${uuidv4().substring(0, 12).replace(/-/g, '')}`,
      reference_id: referenceId,
      amount_inr: amountInr,
      upi: workerUpi,
      provider: "instamojo",
      note: "Simulated payout (Instamojo does not support payouts)",
      timestamp: new Date().toISOString()
    };

  } catch (e) {
    console.warn(`Instamojo simulation failed: ${e.message}`);

    return {
      source: "mock",
      status: "processing",
      payout_id: `pout_mock_${uuidv4().substring(0, 12).replace(/-/g, '')}`,
      reference_id: referenceId,
      amount_inr: Math.floor(amountPaise / 100),
      upi: workerUpi,
      timestamp: new Date().toISOString()
    };
  }
}

module.exports = { initiateUpiPayout };
