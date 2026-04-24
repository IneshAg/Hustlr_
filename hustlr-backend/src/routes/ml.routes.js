const express = require("express");
const router = express.Router();
const axios = require("axios");

const ML_URL =
  process.env.ML_SERVICE_URL || "https://hustlr-ml-complete.onrender.com";
const TIMEOUT = 60000; // 60s — allows for Render free tier cold start (~30-50s)

// Legacy endpoints to prevent jsonDecode crash on old APK
router.post("/nlp", (req, res) => {
  res.status(404).json({
    error:
      "Deprecated in Phase 3. Please update the APK to use the new ML Tester demo.",
  });
});

router.post("/traffic", (req, res) => {
  res.status(404).json({
    error:
      "Deprecated in Phase 3. Please update the APK to use the new ML Tester demo.",
  });
});

// Pass-through proxy routes so the UI ML Data Tester works without direct access to ML url
router.post("/fraud", async (req, res) => {
  try {
    const { data } = await axios.post(`${ML_URL}/fraud-score`, req.body, {
      timeout: TIMEOUT,
    });
    res.json(data);
  } catch (error) {
    if (error.response) {
      res.status(error.response.status).json(error.response.data);
    } else {
      res.status(500).json({ error: error.message });
    }
  }
});

router.post("/iss", async (req, res) => {
  try {
    const { data } = await axios.post(`${ML_URL}/iss`, req.body, {
      timeout: TIMEOUT,
    });
    res.json(data);
  } catch (error) {
    if (error.response) {
      res.status(error.response.status).json(error.response.data);
    } else {
      res.status(500).json({ error: error.message });
    }
  }
});

router.post("/premium", async (req, res) => {
  try {
    const { data } = await axios.post(`${ML_URL}/premium`, req.body, {
      timeout: TIMEOUT,
    });
    res.json(data);
  } catch (error) {
    if (error.response) {
      res.status(error.response.status).json(error.response.data);
    } else {
      res.status(500).json({ error: error.message });
    }
  }
});

// GNN fraud-ring detection proxy.
// Primary: /ml/fraud/gnn-ring-detect
// Alias:   /ml/gnn-ring-detect (keeps tester/manual calls simple)
router.post("/fraud/gnn-ring-detect", async (req, res) => {
  try {
    const { data } = await axios.post(
      `${ML_URL}/fraud/gnn-ring-detect`,
      req.body,
      { timeout: TIMEOUT },
    );
    res.json(data);
  } catch (error) {
    if (error.response) {
      res.status(error.response.status).json(error.response.data);
    } else {
      res.status(500).json({ error: error.message });
    }
  }
});

router.post("/gnn-ring-detect", async (req, res) => {
  try {
    const { data } = await axios.post(
      `${ML_URL}/fraud/gnn-ring-detect`,
      req.body,
      { timeout: TIMEOUT },
    );
    res.json(data);
  } catch (error) {
    if (error.response) {
      res.status(error.response.status).json(error.response.data);
    } else {
      res.status(500).json({ error: error.message });
    }
  }
});

module.exports = router;
