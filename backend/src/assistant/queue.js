/**
 * PostgreSQL tabanlı iş kuyruğu (jobs tablosu). Ek bağımlılık yok.
 *
 * Sözleşme (imzalar sabit):
 *   enqueue(name, payload, {runAt, dedupeKey, orgId, maxAttempts, userId, expiresAt, client}) → {id, deduped}
 *       dedupeKey aynıysa ikinci kayıt EKLENMEZ (mevcut iş döner, deduped:true). Süresi geçen iş çalıştırılmaz ('skipped').
 *   registerHandler(name, fn, {fallback})   fn(payload, job) async; hata fırlatırsa yeniden denenir (geri çekilme 1, 5, 30 dk)
 *       job = {id, name, payload, orgId, userId, attempts, maxAttempts, runAt, dedupeKey}
 *       fallback:true → yalnız o ad için başka işleyici yoksa geçerli; gerçek işleyici (fallback'siz) her zaman onu ezer.
 *   runDue({limit, workerId}) → {claimed, done, retried, failed, skipped, expired, recovered}
 * İşleyiciler src/assistant/handlers/*.js dosyalarından otomatik yüklenir: module.exports.register = (registerHandler) => {...}
 * İşleyiciler İDEMPOTENT olmalıdır (iş iki kez çalışsa bile tek yan etki): bildirimler notify dedupeKey ile korunur.
 * Çoklu worker güvenliği: SELECT … FOR UPDATE SKIP LOCKED ile talep; kilidi tutan çöken worker 5 dk sonra kurtarılır.
 */
const fs = require("fs");
const path = require("path");
const os = require("os");
const db = require("../db");
const clock = require("./clock");

const LOCK_TIMEOUT_MS = Number(process.env.JOB_LOCK_TIMEOUT_MS) || 5 * 60 * 1000;
const JOB_TIMEOUT_MS = Number(process.env.JOB_TIMEOUT_MS) || 60 * 1000;
const BACKOFF_MS = [60 * 1000, 5 * 60 * 1000, 30 * 60 * 1000];
const DEFAULT_WORKER_ID = `${os.hostname()}:${process.pid}`;

const handlers = new Map(); // name -> {fn, fallback}
let loaded = false;

function registerHandler(name, fn, opts = {}) {
  if (typeof name !== "string" || !name || typeof fn !== "function") throw new Error("registerHandler(name, fn) geçersiz");
  const cur = handlers.get(name);
  if (opts.fallback) { if (!cur) handlers.set(name, { fn, fallback: true }); return; }
  handlers.set(name, { fn, fallback: false });
}
function loadHandlers(force = false) {
  if (loaded && !force) return [...handlers.keys()];
  loaded = true;
  const dir = path.join(__dirname, "handlers");
  if (fs.existsSync(dir)) {
    for (const f of fs.readdirSync(dir).filter((x) => x.endsWith(".js") && !x.startsWith("_")).sort()) {
      const mod = require(path.join(dir, f));
      if (mod && typeof mod.register === "function") mod.register(registerHandler);
    }
  }
  return [...handlers.keys()];
}
const hasHandler = (name) => handlers.has(name);

async function enqueue(name, payload = {}, opts = {}) {
  if (typeof name !== "string" || !name) throw new Error("enqueue: iş adı gerekli");
  const q = opts.client || db;
  const runAt = opts.runAt ? new Date(opts.runAt) : clock.now();
  const userId = opts.userId || (payload && payload.userId) || null;
  let orgId = opts.orgId || null;
  if (!orgId) {
    const { defaultOrgId, orgIdForUser } = require("./org");
    orgId = userId ? await orgIdForUser(userId, q) : await defaultOrgId();
  }
  const ins = await q.query(
    `INSERT INTO jobs (org_id, user_id, name, payload, dedupe_key, run_at, expires_at, max_attempts)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
     ON CONFLICT (dedupe_key) DO NOTHING RETURNING id`,
    [orgId, userId, name, JSON.stringify(payload || {}), opts.dedupeKey || null, runAt, opts.expiresAt || null, opts.maxAttempts || 5]
  );
  if (ins.rows[0]) return { id: ins.rows[0].id, deduped: false };
  const ex = await q.query("SELECT id FROM jobs WHERE dedupe_key = $1", [opts.dedupeKey]);
  return { id: ex.rows[0] ? ex.rows[0].id : null, deduped: true };
}

function withTimeout(p, ms) {
  let t;
  const timeout = new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`iş zaman aşımı (${ms} ms)`)), ms); });
  return Promise.race([p, timeout]).finally(() => clearTimeout(t));
}

async function runOne(row, workerId, now) {
  const job = { id: row.id, name: row.name, payload: row.payload || {}, orgId: row.org_id, userId: row.user_id, attempts: row.attempts, maxAttempts: row.max_attempts, runAt: row.run_at, dedupeKey: row.dedupe_key };
  const h = handlers.get(row.name);
  try {
    if (!h) throw new Error(`kayıtlı işleyici yok: ${row.name}`);
    await withTimeout(Promise.resolve(h.fn(job.payload, job)), JOB_TIMEOUT_MS);
    await db.query(`UPDATE jobs SET status='done', finished_at=$3, last_error=NULL, locked_by=NULL, locked_at=NULL WHERE id=$1 AND locked_by=$2 AND status='running'`, [row.id, workerId, now]);
    return "done";
  } catch (err) {
    const msg = String((err && err.message) || err).slice(0, 1000);
    if (row.attempts >= row.max_attempts) {
      await db.query(`UPDATE jobs SET status='failed', finished_at=$3, last_error=$4, locked_by=NULL, locked_at=NULL WHERE id=$1 AND locked_by=$2 AND status='running'`, [row.id, workerId, now, msg]);
      console.error(`[queue] iş KALICI başarısız ${row.name} ${row.id}: ${msg}`);
      return "failed";
    }
    const delay = BACKOFF_MS[Math.min(row.attempts - 1, BACKOFF_MS.length - 1)];
    await db.query(`UPDATE jobs SET status='queued', run_at=$3, last_error=$4, locked_by=NULL, locked_at=NULL WHERE id=$1 AND locked_by=$2 AND status='running'`, [row.id, workerId, new Date(now.getTime() + delay), msg]);
    return "retried";
  }
}

async function runDue(opts = {}) {
  loadHandlers();
  const limit = opts.limit || 20;
  const workerId = opts.workerId || DEFAULT_WORKER_ID;
  const now = clock.now();
  const res = { claimed: 0, done: 0, retried: 0, failed: 0, skipped: 0, expired: 0, recovered: 0 };

  // 1) çöken worker'ın bıraktığı 'running' işleri kurtar (deneme hakkı bittiyse failed)
  const stale = new Date(now.getTime() - LOCK_TIMEOUT_MS);
  const rec = await db.query(
    `UPDATE jobs SET status = CASE WHEN attempts >= max_attempts THEN 'failed' ELSE 'queued' END,
            last_error = 'kilit zaman aşımı (worker çökmüş olabilir)', locked_by = NULL, locked_at = NULL,
            finished_at = CASE WHEN attempts >= max_attempts THEN $2::timestamptz ELSE NULL END
      WHERE status = 'running' AND locked_at < $1 RETURNING id`, [stale, now]);
  res.recovered = rec.rowCount;

  // 2) süresi geçmiş (kaçırılmış) işler: eski saatte bildirim ATILMAZ
  const exp = await db.query(
    `UPDATE jobs SET status='skipped', last_error='süresi geçti (kaçırıldı)', finished_at=$1
      WHERE status='queued' AND expires_at IS NOT NULL AND expires_at <= $1 RETURNING id`, [now]);
  res.expired = exp.rowCount; res.skipped += exp.rowCount;

  // 3) talep et + çalıştır (partiler halinde)
  for (let batch = 0; batch < 10; batch++) {
    const { rows } = await db.query(
      `UPDATE jobs SET status='running', locked_by=$1, locked_at=$2, attempts = attempts + 1
        WHERE id IN (SELECT id FROM jobs WHERE status='queued' AND run_at <= $2 ORDER BY run_at ASC, created_at ASC LIMIT $3 FOR UPDATE SKIP LOCKED)
        RETURNING *`, [workerId, now, limit]);
    if (rows.length === 0) break;
    rows.sort((a, b) => new Date(a.run_at) - new Date(b.run_at));
    res.claimed += rows.length;
    for (const row of rows) {
      const r = await runOne(row, workerId, now);
      res[r]++;
    }
    if (rows.length < limit) break;
  }
  return res;
}

/** Kuyruk özeti (kalp atışı / sağlık ucu): bekleyen, çalışan, gecikmiş (run_at geçmiş), başarısız */
async function stats() {
  const now = clock.now();
  const { rows } = await db.query(
    `SELECT COUNT(*) FILTER (WHERE status='queued')::int AS queued,
            COUNT(*) FILTER (WHERE status='running')::int AS running,
            COUNT(*) FILTER (WHERE status='queued' AND run_at < $1::timestamptz - interval '2 minutes')::int AS overdue,
            COUNT(*) FILTER (WHERE status='failed' AND finished_at > $1::timestamptz - interval '24 hours')::int AS failed_24h
       FROM jobs`, [now]);
  return rows[0];
}

module.exports = { enqueue, registerHandler, runDue, loadHandlers, hasHandler, stats, BACKOFF_MS };
