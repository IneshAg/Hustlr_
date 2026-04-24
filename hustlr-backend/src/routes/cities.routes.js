const express = require('express');
const { listCityRiskProfiles, getCityRiskProfile } = require('../services/city-risk-service');

const router = express.Router();

router.get('/risk-profiles', (req, res) => {
  res.json({ cities: listCityRiskProfiles() });
});

router.get('/risk-profiles/:city', (req, res) => {
  const p = getCityRiskProfile(req.params.city);
  if (!p) return res.status(404).json({ error: 'Unknown city' });
  res.json(p);
});

module.exports = router;

