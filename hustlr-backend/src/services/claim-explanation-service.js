/**
 * Auto-explanation lines for claim rejections / holds from FPS-style signals.
 */

function buildClaimExplanation(body) {
  const signals = body?.fps_signals && typeof body.fps_signals === 'object'
    ? body.fps_signals
    : body;

  const reasons = [];

  const add = (title, detail, severity = 'warning') => {
    reasons.push({ title, detail, severity });
  };

  if (signals.play_integrity_pass === false || body?.play_integrity_pass === false) {
    add(
      'Device environment',
      'Trust signals did not pass (e.g. emulator, spoofing risk, or failed device checks — no paid attestation API required).',
      'critical',
    );
  }
  if (signals.is_mock_location === true || body?.is_mock_location === true) {
    add('Mock location', 'Mock / spoofed GPS was active during the claim window.', 'critical');
  }
  if (Number(signals.gps_zone_mismatch) === 1 || Number(body?.gps_zone_mismatch) === 1) {
    add('GPS zone mismatch', 'Reported location does not match assigned delivery zone history.', 'warning');
  }
  if (Number(signals.wifi_home_ssid) === 1) {
    add('Home Wi‑Fi pattern', 'Network signature consistent with home broadband during shift.', 'warning');
  }
  if (Number(signals.claim_latency_under30s) === 1) {
    add('Claim latency', 'Claim filed unusually fast after disruption start (< 30s).', 'warning');
  }
  if (Number(signals.gps_jitter_perfect) === 1) {
    add('GPS jitter', 'Movement trace lacks natural rider jitter (possible injection).', 'warning');
  }
  if (Number(signals.barometer_mismatch) === 1) {
    add('Barometer', 'Pressure trace inconsistent with outdoor riding in reported weather.', 'info');
  }
  if (Number(signals.coordinated_surge_suspect) === 1) {
    add('Coordinated surge', 'Batch pattern suggests coordinated filings in the same window.', 'warning');
  }
  if (Number(signals.ring_cluster_suspect) === 1) {
    add('Ring cluster', 'Device install graph overlaps known syndicate cluster.', 'warning');
  }
  if (Number(signals.simultaneous_zone_claims) >= 4) {
    add('Multi-zone activity', `High simultaneous zone claims (${signals.simultaneous_zone_claims}).`, 'warning');
  }
  if (Number(signals.fps_score) >= 0.61 || body?.fps_tier === 'RED') {
    add('Composite fraud score', 'Overall FPS exceeded auto-approval threshold — manual review required.', 'critical');
  }

  if (reasons.length === 0) {
    add(
      'Manual review',
      'No single dominant signal; claim held for Sunday batch or human verification.',
      'info',
    );
  }

  return {
    generated_at: new Date().toISOString(),
    reasons,
    summary: reasons.map((r) => r.title).join(' · '),
  };
}

module.exports = { buildClaimExplanation };
