const axios = require("axios");
const { FALLBACKS } = require("./fallback-service");

const NEWSAPI_KEY = process.env.NEWSAPI_KEY;
const NEWSDATA_API_KEY = process.env.NEWSDATA_API_KEY;
const BRAVE_KEY = process.env.BRAVE_SEARCH_KEY;

const BANDH_KEYWORDS = [
  "bandh",
  "curfew",
  "strike",
  "section 144",
  "road blocked",
  "shutdown",
  "hartal",
  "protest blocked",
];
const CITY_KEYWORDS = {
  "adyar dark store zone": ["chennai", "adyar", "tamil nadu"],
  "hitech city": ["hyderabad", "hitech city", "telangana"],
  default: ["chennai"],
};

function _scoreArticles(articles) {
  const matched = new Set();
  articles.forEach((article) => {
    const text = (
      (article.title || "") +
      " " +
      (article.description || "")
    ).toLowerCase();
    BANDH_KEYWORDS.forEach((kw) => {
      if (text.includes(kw)) matched.add(kw);
    });
  });
  const confidence = Math.min(matched.size / 3, 1.0);
  return { confidence, matchedKeywords: Array.from(matched) };
}

async function checkBandhNLP(zone = "adyar dark store zone") {
  const normalizedZone = zone.toLowerCase();
  const cityTerms = CITY_KEYWORDS[normalizedZone] || CITY_KEYWORDS["default"];

  const query = `(${BANDH_KEYWORDS.join(" OR ")}) AND (${cityTerms.join(" OR ")})`;

  // Try NewsAPI
  try {
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000)
      .toISOString()
      .split("T")[0];
    const res = await axios.get("https://newsapi.org/v2/everything", {
      timeout: 5000,
      params: {
        q: query,
        from: yesterday,
        language: "en",
        sortBy: "publishedAt",
        pageSize: 10,
        apiKey: NEWSAPI_KEY,
      },
    });

    const articles = res.data.articles || [];
    const { confidence, matchedKeywords } = _scoreArticles(articles);

    console.log(
      `[Bandh NLP] LIVE NewsAPI | zone=${zone} | confidence=${confidence.toFixed(2)}`,
    );
    return {
      source: "live_newsapi",
      zone: zone,
      bandh_detected: confidence >= 0.6,
      confidence: parseFloat(confidence.toFixed(3)),
      matched_keywords: matchedKeywords,
      article_count: articles.length,
      trigger_threshold: 0.6,
      timestamp: new Date().toISOString(),
    };
  } catch (e) {
    console.warn(
      `[NewsAPI] failed: ${e.response?.data?.message || e.message} — trying NewsData`,
    );
  }

  // Try NewsData
  try {
    if (NEWSDATA_API_KEY) {
      const res = await axios.get("https://newsdata.io/api/1/latest", {
        timeout: 5000,
        params: {
          apikey: NEWSDATA_API_KEY,
          country: "in",
          language: "en",
          size: 10,
          q: `${cityTerms.join(" OR ")} AND (${BANDH_KEYWORDS.join(" OR ")})`,
        },
      });

      const rows = res.data?.results || [];
      const articles = rows.map((r) => ({
        title: r.title || "",
        description: r.description || r.content || "",
      }));
      const { confidence, matchedKeywords } = _scoreArticles(articles);

      console.log(
        `[Bandh NLP] LIVE NewsData | zone=${zone} | confidence=${confidence.toFixed(2)}`,
      );
      return {
        source: "live_newsdata",
        zone: zone,
        bandh_detected: confidence >= 0.6,
        confidence: parseFloat(confidence.toFixed(3)),
        matched_keywords: matchedKeywords,
        article_count: rows.length,
        trigger_threshold: 0.6,
        timestamp: new Date().toISOString(),
      };
    }
  } catch (e) {
    console.warn(
      `[NewsData] failed: ${e.response?.data?.results?.message || e.message} — trying Brave Search`,
    );
  }

  // Try Brave Search
  try {
    if (BRAVE_KEY) {
      const res = await axios.get(
        "https://api.search.brave.com/res/v1/web/search",
        {
          headers: {
            Accept: "application/json",
            "X-Subscription-Token": BRAVE_KEY,
          },
          params: { q: query, count: 10, freshness: "pd" },
          timeout: 5000,
        },
      );

      const results = res.data.web?.results || [];
      const combinedText = results
        .map((r) => (r.title || "") + " " + (r.description || ""))
        .join(" ")
        .toLowerCase();

      const matched = BANDH_KEYWORDS.filter((kw) => combinedText.includes(kw));
      const confidence = Math.min(matched.length / 3, 1.0);

      console.log(
        `[Bandh NLP] FALLBACK Brave | zone=${zone} | confidence=${confidence.toFixed(2)}`,
      );
      return {
        source: "fallback_brave",
        zone: zone,
        bandh_detected: confidence >= 0.6,
        confidence: parseFloat(confidence.toFixed(3)),
        matched_keywords: matched,
        article_count: results.length,
        trigger_threshold: 0.6,
        timestamp: new Date().toISOString(),
      };
    } else {
      console.warn(`[Brave Search] Key not provided — skipping Brave fallback`);
    }
  } catch (e) {
    console.warn(`[Brave Search] also failed: ${e.message} — using mock`);
  }

  // Mock
  return {
    source: "mock",
    zone: zone,
    bandh_detected: false,
    confidence: 0.0,
    matched_keywords: [],
    article_count: 0,
    trigger_threshold: 0.6,
    timestamp: new Date().toISOString(),
  };
}

module.exports = { checkBandhNLP };

