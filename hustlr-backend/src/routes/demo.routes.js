// routes/demo.routes.js
// Demo disruption control panel routes for testing rain, heat waves, and other scenarios

const express = require('express');
const router = express.Router();
const { requireSession } = require('../middleware/session-auth');
const demoDisruptionControl = require('../services/demo-disruption-control');

// GET /demo/status - Get demo control panel status
router.get('/status', requireSession, async (req, res) => {
  try {
    const response = await demoDisruptionControl.getDemoStatus(req, res);
    return res.json(response);
  } catch (error) {
    console.error('[Demo Routes] Status error:', error);
    return res.status(500).json({ error: 'Failed to get demo status' });
  }
});

// POST /demo/disruption - Create a demo disruption
router.post('/disruption', requireSession, async (req, res) => {
  try {
    const response = await demoDisruptionControl.createDemoDisruption(req, res);
    return res.json(response);
  } catch (error) {
    console.error('[Demo Routes] Create disruption error:', error);
    return res.status(500).json({ error: 'Failed to create disruption' });
  }
});

// POST /demo/deactivate/:disruption_id - Deactivate a demo disruption
router.post('/deactivate/:disruption_id', requireSession, async (req, res) => {
  try {
    const response = await demoDisruptionControl.deactivateDisruption(req, res);
    return res.json(response);
  } catch (error) {
    console.error('[Demo Routes] Deactivate error:', error);
    return res.status(500).json({ error: 'Failed to deactivate disruption' });
  }
});

// GET /demo/active - Get all active demo disruptions
router.get('/active', requireSession, async (req, res) => {
  try {
    const response = await demoDisruptionControl.getActiveDisruptions(req, res);
    return res.json(response);
  } catch (error) {
    console.error('[Demo Routes] Active disruptions error:', error);
    return res.status(500).json({ error: 'Failed to get active disruptions' });
  }
});

module.exports = router;


