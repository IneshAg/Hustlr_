const crypto = require("crypto");
const { GoogleAuth } = require("google-auth-library");
const axios = require("axios");

const NONCE_TTL_MS = 5 * 60 * 1000;
const nonceStore = new Map();

/** Bonus / penalty applied to numeric fraud_score after ML + rules (explicit judge-visible hook). */
const FRAUD_DELTA_PASS = -10;
const FRAUD_DELTA_FAIL = 30;

const JUDGE_NOTE_SIMULATED =
  "Play Integrity is integrated at the architecture level. This verdict is simulated (no paid Google decode in this mode); swap PLAY_INTEGRITY_SIMULATED=false and add a service account for production. Do not claim tamper-proof or fully secured — this is a transparent demo pipeline.";

function pruneNonces() {
  const now = Date.now();
  for (const [n, exp] of nonceStore) {
    if (exp < now) nonceStore.delete(n);
  }
}

function issueNonce() {
  pruneNonces();
  const nonce = crypto.randomBytes(24).toString("base64");
  nonceStore.set(nonce, Date.now() + NONCE_TTL_MS);
  return { nonce, expires_in: Math.floor(NONCE_TTL_MS / 1000) };
}

function consumeNonce(nonce) {
  if (!nonce || typeof nonce !== "string") return false;
  pruneNonces();
  const exp = nonceStore.get(nonce);
  if (!exp || exp < Date.now()) {
    nonceStore.delete(nonce);
    return false;
  }
  nonceStore.delete(nonce);
  return true;
}

function isSimulatedMode() {
  return process.env.PLAY_INTEGRITY_SIMULATED === "true";
}

function mockVerdictPass() {
  return {
    deviceIntegrity: {
      deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"],
    },
    appIntegrity: {
      appRecognitionVerdict: "PLAY_RECOGNIZED",
    },
  };
}

function mockVerdictFail() {
  return {
    deviceIntegrity: { deviceRecognitionVerdict: [] },
    appIntegrity: { appRecognitionVerdict: "UNRECOGNIZED_VERSION" },
  };
}

/**
 * Apply after base fraud_score is computed: valid integrity → -10, invalid → +30.
 */
function applyPlayIntegrityFraudDelta(score, integrityPass) {
  if (integrityPass) {
    return {
      score: Math.max(0, score + FRAUD_DELTA_PASS),
      delta: FRAUD_DELTA_PASS,
      reason: "integrity_trust_bonus",
    };
  }
  return {
    score: Math.min(100, score + FRAUD_DELTA_FAIL),
    delta: FRAUD_DELTA_FAIL,
    reason: "integrity_fail_penalty",
  };
}

function buildGoogleAuth() {
  const raw = process.env.PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON;
  if (raw && raw.trim()) {
    return new GoogleAuth({
      credentials: JSON.parse(raw),
      scopes: ["https://www.googleapis.com/auth/playintegrity"],
    });
  }
  const keyFile = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (keyFile && keyFile.trim()) {
    return new GoogleAuth({
      keyFile,
      scopes: ["https://www.googleapis.com/auth/playintegrity"],
    });
  }
  return null;
}

async function decodeIntegrityToken(integrityToken, packageName) {
  const auth = buildGoogleAuth();
  if (!auth) {
    const err = new Error("missing_credentials");
    err.code = "missing_credentials";
    throw err;
  }

  const client = await auth.getClient();
  const { token: accessToken } = await client.getAccessToken();
  if (!accessToken) {
    const err = new Error("no_access_token");
    err.code = "no_access_token";
    throw err;
  }

  const url = `https://playintegrity.googleapis.com/v1/${encodeURIComponent(packageName)}:decodeIntegrityToken`;
  const response = await axios.post(
    url,
    { integrityToken },
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      timeout: 20000,
      validateStatus: () => true,
    },
  );

  const data = response.data;
  if (response.status >= 400 || data.error) {
    const ge = data.error || { message: `HTTP ${response.status}` };
    const err = new Error(ge.message || "play_integrity_api_error");
    err.code = "google_api_error";
    err.details = ge;
    err.status = response.status;
    throw err;
  }

  return data;
}

function evaluateVerdicts(payloadExternal) {
  if (!payloadExternal) {
    return { pass: false, reason: "empty_payload", summary: {} };
  }

  const app = payloadExternal.appIntegrity?.appRecognitionVerdict;
  const deviceList = payloadExternal.deviceIntegrity?.deviceRecognitionVerdict;
  const devices = Array.isArray(deviceList)
    ? deviceList
    : deviceList
      ? [deviceList]
      : [];

  const relaxedApp = process.env.PLAY_INTEGRITY_RELAXED_APP === "true";
  const appOk =
    app === "PLAY_RECOGNIZED" ||
    (relaxedApp && (app === "UNRECOGNIZED_VERSION" || app === "UNEVALUATED"));

  const deviceOk =
    devices.includes("MEETS_STRONG_INTEGRITY") ||
    devices.includes("MEETS_DEVICE_INTEGRITY");

  const relaxedDevice = process.env.PLAY_INTEGRITY_RELAXED_DEVICE === "true";
  const pass = appOk && (deviceOk || relaxedDevice);

  return {
    pass,
    reason: pass
      ? "ok"
      : !appOk
        ? `app_verdict:${app || "missing"}`
        : `device_verdict:${devices.join(",") || "missing"}`,
    summary: {
      app_recognition_verdict: app,
      device_recognition_verdict: devices,
      request_package_name: payloadExternal.requestDetails?.requestPackageName,
    },
  };
}

/**
 * Simulated: returns mock verdict JSON (no Google). Real: decodeIntegrityToken + nonce.
 * Options: skipNonce, simulateFail (simulated only — demo a failing device)
 */
async function verifyIntegrityToken(
  integrityToken,
  packageName,
  { skipNonce = false, simulateFail = false } = {},
) {
  if (isSimulatedMode()) {
    if (
      !integrityToken ||
      typeof integrityToken !== "string" ||
      integrityToken.trim() === ""
    ) {
      return {
        ok: false,
        play_integrity_pass: false,
        evaluated: false,
        mode: "simulated_no_token",
        judge_note: JUDGE_NOTE_SIMULATED,
        package_name: packageName,
      };
    }

    const pass = !simulateFail;
    const mock = pass ? mockVerdictPass() : mockVerdictFail();
    return {
      ok: pass,
      play_integrity_pass: pass,
      evaluated: true,
      nonce_valid: true,
      verdict: pass ? "simulated:pass" : "simulated:fail",
      summary: pass
        ? {
            app_recognition_verdict: "PLAY_RECOGNIZED",
            device_recognition_verdict: ["MEETS_DEVICE_INTEGRITY"],
          }
        : {
            app_recognition_verdict: "UNRECOGNIZED_VERSION",
            device_recognition_verdict: [],
          },
      mock_verdict: mock,
      mode: "simulated_hackathon",
      judge_note: JUDGE_NOTE_SIMULATED,
      package_name: packageName,
    };
  }

  const data = await decodeIntegrityToken(integrityToken, packageName);
  const ext = data.tokenPayloadExternal;
  const requestNonce = ext?.requestDetails?.nonce;

  let nonceOk = true;
  if (process.env.PLAY_INTEGRITY_SKIP_NONCE_CHECK !== "true" && !skipNonce) {
    nonceOk = consumeNonce(requestNonce);
  }

  const verdict = evaluateVerdicts(ext);

  return {
    ok: verdict.pass && nonceOk,
    play_integrity_pass: verdict.pass && nonceOk,
    evaluated: true,
    nonce_valid: nonceOk,
    verdict: verdict.reason,
    summary: verdict.summary,
    mode: "google_decode",
    raw_request_details: ext?.requestDetails
      ? {
          request_package_name: ext.requestDetails.requestPackageName,
          timestamp_millis: ext.requestDetails.timestampMillis,
        }
      : undefined,
  };
}

function isConfigured() {
  return !!(
    (process.env.PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON &&
      process.env.PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON.trim()) ||
    (process.env.GOOGLE_APPLICATION_CREDENTIALS &&
      process.env.GOOGLE_APPLICATION_CREDENTIALS.trim())
  );
}

function shouldRunIntegrityPipeline() {
  if (process.env.PLAY_INTEGRITY_BYPASS_DEV === "true") return false;
  return isSimulatedMode() || isConfigured();
}

module.exports = {
  issueNonce,
  consumeNonce,
  decodeIntegrityToken,
  verifyIntegrityToken,
  evaluateVerdicts,
  isConfigured,
  isSimulatedMode,
  shouldRunIntegrityPipeline,
  applyPlayIntegrityFraudDelta,
  mockVerdictPass,
  JUDGE_NOTE_SIMULATED,
};
