/**
 * plan_day — kullanıcı başına günlük işleri planlar (A1 yalnız zamanlamayı yapar; içeriği A2'nin işleyicileri üretir):
 *   'briefing.morning'  (sabah brifingi)   dedupe: briefing.morning:{userId}:{YYYY-MM-DD}
 *   'closure.evening'   (akşam kapanış)    dedupe: closure.evening:{userId}:{YYYY-MM-DD}
 * Saat/gün: kullanıcının notification_prefs'i (yoksa org_settings, yoksa 07:30/18:30) ve saat dilimi (varsayılan Europe/Istanbul).
 * İdempotent: aynı günün işleri tekrar planlanmaz; tercih saati değişirse BEKLEYEN iş yeniden zamanlanır; tercih kapanırsa iptal (skipped).
 * Catch-up: saati geçmiş ama süresi (varsayılan +3,5 sa) dolmamış iş hemen çalışır; süresi dolmuşsa 'skipped' (kaçırıldı) kaydı düşer.
 */
const db = require("../db");
const clock = require("./clock");
const prefsSvc = require("./prefs");

const EXPIRES_AFTER_MS = Number(process.env.PLAN_EXPIRES_AFTER_MS) || 3.5 * 3600 * 1000;
const AUTO_ROLES = ["admin", "muhasebe", "ortak", "personel"]; // prefs satırı yoksa bu roller brifing alır (saha: yalnız açıkça açarsa)
const KINDS = [
  { kind: "morning", job: "briefing.morning", flag: "morning_enabled", time: "morning_time" },
  { kind: "evening", job: "closure.evening", flag: "evening_enabled", time: "evening_time" },
];

async function planForUser(q, user, row, orgTimesCache, now) {
  const org = orgTimesCache.get(user.org_id) || (await prefsSvc.orgTimes(user.org_id));
  orgTimesCache.set(user.org_id, org);
  const p = prefsSvc.effective(row && row.user_id ? row : null, org);
  const eligible = row && row.user_id ? p.enabled : p.enabled && AUTO_ROLES.includes(user.role);
  const date = clock.zonedDateStr(now, p.tz);
  const dow = clock.zonedWeekday(now, p.tz);
  const out = { planned: 0, missed: 0, cancelled: 0, rescheduled: 0 };
  for (const k of KINDS) {
    const key = `${k.job}:${user.id}:${date}`;
    const wanted = eligible && p[k.flag] && p.weekdays.includes(dow);
    if (!wanted) {
      const c = await q.query(`UPDATE jobs SET status='skipped', last_error='tercih kapalı', finished_at=$2 WHERE dedupe_key=$1 AND status='queued'`, [key, now]);
      out.cancelled += c.rowCount;
      continue;
    }
    const runAt = clock.zonedToUtc(date, p[k.time], p.tz);
    const expiresAt = new Date(runAt.getTime() + EXPIRES_AFTER_MS);
    const payload = JSON.stringify({ userId: user.id, date, kind: k.kind });
    if (expiresAt <= now) {
      const r = await q.query(
        `INSERT INTO jobs (org_id, user_id, name, payload, dedupe_key, run_at, expires_at, status, last_error, finished_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,'skipped','süresi geçti (kaçırıldı)',$8) ON CONFLICT (dedupe_key) DO NOTHING`,
        [user.org_id, user.id, k.job, payload, key, runAt, expiresAt, now]);
      out.missed += r.rowCount;
      continue;
    }
    const r = await q.query(
      `INSERT INTO jobs (org_id, user_id, name, payload, dedupe_key, run_at, expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (dedupe_key) DO UPDATE SET run_at = EXCLUDED.run_at, expires_at = EXCLUDED.expires_at
         WHERE jobs.status = 'queued' AND jobs.run_at IS DISTINCT FROM EXCLUDED.run_at
       RETURNING (xmax = 0) AS inserted`,
      [user.org_id, user.id, k.job, payload, key, runAt, expiresAt]);
    if (r.rows[0]) { if (r.rows[0].inserted) out.planned++; else out.rescheduled++; }
  }
  return out;
}

/** Tüm kullanıcılar (tek lider: advisory lock). {leader, users, planned, missed, cancelled, rescheduled} */
async function planAll(opts = {}) {
  const now = clock.now();
  const client = await db.pool.connect();
  const total = { leader: true, users: 0, planned: 0, missed: 0, cancelled: 0, rescheduled: 0 };
  try {
    await client.query("BEGIN");
    const lock = await client.query("SELECT pg_try_advisory_xact_lock(hashtext('assistant.plan_day')) AS ok");
    if (!lock.rows[0].ok) { await client.query("ROLLBACK"); return { ...total, leader: false }; }
    const { rows } = await client.query(
      `SELECT u.id AS uid, u.org_id AS uorg, u.role AS urole, np.*
         FROM users u LEFT JOIN notification_prefs np ON np.user_id = u.id`);
    const cache = new Map();
    for (const r of rows) {
      const user = { id: r.uid, org_id: r.uorg, role: r.urole };
      const row = r.user_id ? r : null;
      const o = await planForUser(client, user, row, cache, now);
      total.users++; for (const k of ["planned", "missed", "cancelled", "rescheduled"]) total[k] += o[k];
    }
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
  return total;
}

/** Tek kullanıcı (tercihler değişince API'den çağrılır: yeni saat hemen geçerli olur) */
async function planUser(userId) {
  const now = clock.now();
  const { rows } = await db.query(
    `SELECT u.id AS uid, u.org_id AS uorg, u.role AS urole, np.* FROM users u LEFT JOIN notification_prefs np ON np.user_id = u.id WHERE u.id = $1`, [userId]);
  if (!rows[0]) return null;
  const r = rows[0];
  return planForUser(db, { id: r.uid, org_id: r.uorg, role: r.urole }, r.user_id ? r : null, new Map(), now);
}

module.exports = { planAll, planUser, KINDS, EXPIRES_AFTER_MS };
