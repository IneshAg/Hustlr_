const axios = require("axios");

function getGeminiApiKey() {
  return (
    process.env.GEMINI_API_KEY ||
    process.env.GOOGLE_API_KEY ||
    process.env.GOOGLE_GENAI_API_KEY ||
    ""
  );
}

function getGeminiModel() {
  return process.env.GEMINI_MODEL || "gemini-2.5-flash";
}

const README_LIMITS = {
  weeklyPlanPrices: [35, 49, 79],
  dailyCaps: [100, 150, 250],
  weeklyCaps: [210, 340, 500],
  fullOnlyTriggers: ["cyclone", "extreme rain", "heavy traffic"],
};

function _extractInrNumbers(text) {
  if (!text || typeof text !== "string") return [];
  const matches = text.match(/₹\s*(\d+)/g) || [];
  return matches
    .map((m) => {
      const n = Number(String(m).replace(/[^0-9]/g, ""));
      return Number.isFinite(n) ? n : null;
    })
    .filter((n) => n !== null);
}

function _mentionsWeeklyPlanPrice(text) {
  if (!text || typeof text !== "string") return null;
  const m = text.match(/₹\s*(\d+)\s*\/\s*week/i);
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) ? n : null;
}

function respectsReadmeLimits(headline, coverageNudge, baseAdvisor) {
  const merged = `${headline} ${coverageNudge}`;
  const lower = merged.toLowerCase();

  // Keep weekly plan references aligned with canonical pricing.
  const weeklyMention = _mentionsWeeklyPlanPrice(merged);
  if (
    weeklyMention !== null &&
    !README_LIMITS.weeklyPlanPrices.includes(weeklyMention)
  ) {
    return false;
  }

  // If caps are mentioned explicitly, they must not exceed README hard caps.
  const hasCapWord = /\bcap\b/i.test(merged);
  if (hasCapWord) {
    const inrValues = _extractInrNumbers(merged);
    const maxAllowed = Math.max(...README_LIMITS.weeklyCaps);
    if (inrValues.some((n) => n > maxAllowed)) return false;
  }

  // Full-only trigger gate: never imply lower-tier access.
  const mentionsBasicOrStandard = /\bbasic\b|\bstandard\b/i.test(lower);
  const mentionsFullOnlyTrigger = README_LIMITS.fullOnlyTriggers.some((t) =>
    lower.includes(t),
  );
  if (mentionsBasicOrStandard && mentionsFullOnlyTrigger) return false;

  // Preserve existing numeric guidance from base advisor where possible.
  const baseWeekly = _mentionsWeeklyPlanPrice(
    baseAdvisor?.coverage_nudge || "",
  );
  if (
    baseWeekly !== null &&
    weeklyMention !== null &&
    baseWeekly !== weeklyMention
  ) {
    return false;
  }

  return true;
}

function sanitizeAdvisorText(text) {
  if (!text || typeof text !== "string") return "";
  const trimmed = text.trim();
  if (!trimmed) return "";

  // Avoid hard guarantees or manipulative phrasing in user-facing risk text.
  const banned = [
    /\bcovers that\b/i,
    /\bguarantee(d)?\b/i,
    /don't lose out again/i,
    /\byou missed\b/i,
    /\bmust buy\b/i,
    /\b100%\b/i,
  ];
  if (banned.some((rx) => rx.test(trimmed))) return "";

  return trimmed;
}

async function personalizeAdvisorCopy(baseAdvisor, context = {}) {
  const geminiApiKey = getGeminiApiKey();
  if (!geminiApiKey) return null;
  const geminiModel = getGeminiModel();

  const payload = {
    contents: [
      {
        role: "user",
        parts: [
          {
            text: [
              "You are a concise insurance risk copywriter for gig workers.",
              "Rewrite ONLY headline and coverage_nudge to be personalized, clear and non-alarmist.",
              "Use estimated/probabilistic language, not guarantees.",
              "Do not use manipulative urgency or fear-based wording.",
              "If you reference coverage, mention that terms apply.",
              "Use ONLY these canonical README limits when mentioning plan numbers:",
              "Weekly plan prices: ₹35 (Basic), ₹49 (Standard), ₹79 (Full).",
              "Tier-locked caps: Basic ₹100/day & ₹210/week, Standard ₹150/day & ₹340/week, Full ₹250/day & ₹500/week.",
              "Never claim or imply any cap above ₹500/week.",
              "Full-only hard gates: Cyclone, Extreme Rain, Heavy Traffic.",
              "Keep headline <= 140 chars, nudge <= 180 chars.",
              "Do not change amounts/numbers/tier logic.",
              'Return strict JSON: {"headline":"...","coverage_nudge":"..."}',
              `Input advisor: ${JSON.stringify(baseAdvisor)}`,
              `Context: ${JSON.stringify({ zone: context.zone, city: context.city, weather: context.weather, nudge: context.nudge })}`,
            ].join("\n"),
          },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.4,
      maxOutputTokens: 180,
      responseMimeType: "application/json",
    },
  };

  try {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(geminiModel)}:generateContent?key=${encodeURIComponent(geminiApiKey)}`;
    const res = await axios.post(url, payload, { timeout: 2500 });
    const text = res.data?.candidates?.[0]?.content?.parts?.[0]?.text || "";

    if (!text || typeof text !== "string") return null;

    const parsed = JSON.parse(text);
    const headline = sanitizeAdvisorText(String(parsed?.headline || ""));
    const coverage_nudge = sanitizeAdvisorText(
      String(parsed?.coverage_nudge || ""),
    );
    if (!headline || !coverage_nudge) return null;
    if (headline.length > 140 || coverage_nudge.length > 180) return null;
    if (!respectsReadmeLimits(headline, coverage_nudge, baseAdvisor))
      return null;

    return { headline, coverage_nudge, _copy_source: "gemini" };
  } catch {
    return null;
  }
}

module.exports = {
  personalizeAdvisorCopy,
};
