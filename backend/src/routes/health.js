const express = require("express");
const db = require("../db");
const { optionalAuth } = require("../middleware/auth");
const queue = require("../assistant/queue");
const fcm = require("../assistant/fcmv1");

const router = express.Router();
const STALE_S = Number(process.env.WORKER_STALE_SECONDS) || 120;

/**
 * GET /api/health/worker — herkese açık (izleme için): {status: ok|stale|down, last_tick_age_seconds, overdue_jobs}.
 * ok → 200; stale/down → 503. Oturumlu admin ayrıca ayrıntı görür (worker listesi, kuyruk sayıları, FCM durumu).
 */
router.get("/worker", optionalAuth, async (req, res) => {
  const { rows } = await db.query("SELECT worker_id, host, pid, version, started_at, last_tick_at, ticks, stats, last_error FROM worker_heartbeats ORDER BY last_tick_at DESC LIMIT 10");
  const q = await queue.stats();
  const age = rows[0] ? Math.max(0, Math.round((Date.now() - new Date(rows[0].last_tick_at).getTime()) / 1000)) : null;
  const status = age === null ? "down" : age <= STALE_S ? "ok" : "stale";
  const body = { status, last_tick_age_seconds: age, overdue_jobs: q.overdue };
  if (req.user && req.user.role === "admin") Object.assign(body, { workers: rows, queue: q, fcm_enabled: fcm.isEnabled() });
  res.status(status === "ok" ? 200 : 503).json(body);
});

module.exports = router;
