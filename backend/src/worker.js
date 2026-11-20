/**
 * Asistan worker'ı — API sürecinden BAĞIMSIZ, ayrı PM2 uygulaması (ecosystem.config.js: xcontrol-worker). Tek komut: `node src/worker.js`
 *
 * Her tick (WORKER_TICK_MS, varsayılan 30 sn):
 *   1) plan_day işini (10 dk dilimi başına bir kez; idempotent) kuyruğa koyar → günlük brifing/kapanış işleri planlanır
 *      (açılışta ve gece yarısı geçişinde de otomatik: catch-up)
 *   2) vadesi gelmiş işleri çalıştırır (SKIP LOCKED: birden fazla worker çalışsa da iş çift çalışmaz; süresi geçenler 'skipped')
 *   3) bildirim outbox'ını gönderir (FCM yapılandırılmamışsa devre dışı: kayıtlar bildirim kutusunda 'beklemede' kalır)
 *   4) kalp atışını worker_heartbeats'e yazar (GET /api/health/worker)
 * SIGTERM/SIGINT: yeni tick başlatmaz, çalışanı bitirir, bağlantıyı kapatır (PM2 kill_timeout ile uyumlu).
 */
require("dotenv").config();
const os = require("os");
const crypto = require("crypto");
const db = require("./db");
const clock = require("./assistant/clock");
const queue = require("./assistant/queue");
const sender = require("./assistant/sender");
const fcm = require("./assistant/fcmv1");
const pkg = require("../package.json");

const TICK_MS = Math.max(Number(process.env.WORKER_TICK_MS) || 30000, 100);
const BATCH = Number(process.env.WORKER_BATCH) || 20;
const WORKER_ID = `${os.hostname()}:${process.pid}:${crypto.randomBytes(3).toString("hex")}`;
const SLOT_MS = 10 * 60 * 1000;

let ticks = 0, started = new Date();

async function heartbeat(stats, lastError) {
  await db.query(
    `INSERT INTO worker_heartbeats (worker_id, host, pid, version, started_at, last_tick_at, ticks, stats, last_error)
     VALUES ($1,$2,$3,$4,$5,now(),$6,$7,$8)
     ON CONFLICT (worker_id) DO UPDATE SET last_tick_at = now(), ticks = EXCLUDED.ticks, stats = EXCLUDED.stats, last_error = EXCLUDED.last_error`,
    [WORKER_ID, os.hostname(), process.pid, pkg.version, started, ticks, JSON.stringify(stats || {}), lastError ? String(lastError).slice(0, 500) : null]);
}

/** Tek tick (testler de doğrudan çağırır) */
async function tick() {
  queue.loadHandlers();
  ticks++;
  const now = clock.now();
  const stats = {};
  let lastError = null;
  try {
    const slot = Math.floor(now.getTime() / SLOT_MS);
    await queue.enqueue("plan_day", {}, { dedupeKey: `plan_day:${slot}`, runAt: now, expiresAt: new Date((slot + 1) * SLOT_MS), maxAttempts: 3 });
    await queue.enqueue("housekeeping", {}, { dedupeKey: `housekeeping:${clock.istanbulDateStr(now)}`, runAt: clock.zonedToUtc(clock.istanbulDateStr(now), "03:30"), expiresAt: new Date(now.getTime() + 20 * 3600 * 1000), maxAttempts: 2 });
    const r1 = await queue.runDue({ workerId: WORKER_ID, limit: BATCH });
    stats.jobs = r1;
    if (r1.claimed > 0) { // plan_day yeni işler üretmiş olabilir: aynı tick'te bir tur daha
      const r2 = await queue.runDue({ workerId: WORKER_ID, limit: BATCH });
      for (const k of Object.keys(r2)) r1[k] += r2[k];
    }
    stats.sender = await sender.sendDue();
    stats.queue = await queue.stats();
  } catch (err) {
    lastError = err.message;
    console.error("[worker] tick hatası:", err.message);
  }
  try { await heartbeat(stats, lastError); } catch (e) { console.error("[worker] kalp atışı yazılamadı:", e.message); }
  return { stats, error: lastError };
}

async function main() {
  console.log(`[worker] başladı ${WORKER_ID} (tick ${TICK_MS} ms, FCM ${fcm.isEnabled() ? "AÇIK" : "kapalı/dryRun"})`);
  let stopping = false, wake = null;
  const stop = (sig) => { console.log(`[worker] ${sig} alındı, kapanıyor`); stopping = true; if (wake) wake(); };
  process.on("SIGTERM", () => stop("SIGTERM"));
  process.on("SIGINT", () => stop("SIGINT"));
  process.on("unhandledRejection", (e) => console.error("[worker] yakalanmamış söz hatası:", e && e.message ? e.message : e));
  while (!stopping) {
    await tick();
    if (stopping) break;
    await new Promise((r) => { const t = setTimeout(r, TICK_MS); wake = () => { clearTimeout(t); r(); }; });
  }
  await db.pool.end().catch(() => {});
  process.exit(0);
}

if (require.main === module) main().catch((e) => { console.error("[worker] ölümcül hata:", e); process.exit(1); });
module.exports = { tick, main, WORKER_ID };
