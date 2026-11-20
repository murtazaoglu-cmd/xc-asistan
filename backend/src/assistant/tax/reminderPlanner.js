/**
 * Vergi takvimi / tahsilat hatırlatmalarını A1 iş kuyruğuna (jobs) PLANLAR. Gönderim handlers/tax.js içindeki işleyicilerdedir.
 *
 *   'tax.plan'          kuruluş+kullanıcı başına yaklaşan takvim oluşumları için 'tax.remind' işlerini, açık alacağı olan kullanıcılar için
 *                       günlük 'receivable.remind' işini planlar; kendini ertesi gün 03:45'e yeniden zamanlar (zincir).
 *   'tax.remind'        payload {userId, key, dueDate, offset}   dedupe: tax.remind:{userId}:{key}:{dueDate}:T{offset}
 *   'receivable.remind' payload {userId, date}                   dedupe: receivable.remind:{userId}:{date}
 * Zincir başlangıcı: worker'a dokunmadan, API'nin vergi uçları bootstrap() çağırır (idempotent; gün başına tek 'tax.plan'). İsterseniz worker tick'ine
 * `queue.enqueue("tax.plan", {}, {dedupeKey: `tax.plan:${clock.istanbulDateStr()}`})` eklenebilir; eklenmese de zincir kendini sürdürür.
 * Saat/dil: kullanıcının bildirim tercihleri (morning_time, tz, enabled) — brifing ile aynı saat. Hatırlatma günü hafta sonu olsa da planlanır (son gün kritik).
 */
const db = require("../../db");
const clock = require("../clock");
const queue = require("../queue");
const prefsSvc = require("../prefs");
const TC = require("./taxCalendar");
const { addDays } = require("./dates");

const ELIGIBLE_ROLES = ["admin", "muhasebe", "ortak"];       // personel/saha finans verisi görmez → hatırlatma da almaz
const OFFSETS = [7, 3, 1, 0];                                 // son günden kaç gün önce (M8: T−7, T−3, T−1 ve son gün)
const HORIZON_DAYS = Math.max(...OFFSETS) + 1;
const TAX_EXPIRE_AFTER_MS = 18 * 3600 * 1000;
const RECV_EXPIRE_AFTER_MS = 10 * 3600 * 1000;
let lastBootstrapDay = null;

/** Takvim kalemleri + tatiller + statü (kuruluş başına, planlama turu içinde önbellek) */
async function loadOrgCalendar(orgId, today) {
  const [items, hol, st] = await Promise.all([
    db.query("SELECT *, due_date::text AS due_date FROM tax_calendar_items WHERE org_id = $1 AND enabled", [orgId]),
    db.query("SELECT day::text AS day, name, half_day, verified FROM holidays_tr WHERE org_id = $1 AND day BETWEEN $2::date AND $3::date", [orgId, addDays(today, -45), addDays(today, 120)]),
    db.query("SELECT tax_status FROM org_tax_settings WHERE org_id = $1", [orgId]),
  ]);
  return { items: items.rows, holidays: hol.rows, statu: (st.rows[0] && st.rows[0].tax_status) || null };
}

/** Statüye göre ilgili oluşumlar: statü biliniyorsa 'hepsi' + statü; bilinmiyorsa yalnız 'hepsi' */
function occurrencesFor(cal, { from, to, today }) {
  const items = cal.items.filter((i) => i.applies_to === "hepsi" || (cal.statu && i.applies_to === cal.statu));
  return TC.occurrences(items, { from, to, holidays: cal.holidays, today, appliesTo: cal.statu || undefined });
}

async function planUserTax(user, cal, today, now) {
  const prefs = await prefsSvc.getPrefs(user.id);
  if (!prefs.enabled) return 0;
  let n = 0;
  const occs = occurrencesFor(cal, { from: today, to: addDays(today, HORIZON_DAYS), today });
  for (const o of occs) {
    for (const off of OFFSETS) {
      const day = addDays(o.due_date, -off);
      if (day < today) continue;              // eşik günü geçti: geriye dönük hatırlatma yok
      const runAt = clock.zonedToUtc(day, prefs.morning_time || "07:30", prefs.tz);
      const endOfDue = clock.zonedToUtc(addDays(o.due_date, 1), "00:00", prefs.tz);
      const expiresAt = new Date(Math.min(runAt.getTime() + TAX_EXPIRE_AFTER_MS, endOfDue.getTime()));
      if (expiresAt <= now) continue;
      const r = await queue.enqueue("tax.remind", { userId: user.id, key: o.key, dueDate: o.due_date, offset: off }, {
        runAt, expiresAt, userId: user.id, orgId: user.org_id, dedupeKey: `tax.remind:${user.id}:${o.key}:${o.due_date}:T${off}`, maxAttempts: 3,
      });
      if (!r.deduped) n++;
    }
  }
  return n;
}

async function planUserReceivables(user, today, now) {
  const prefs = await prefsSvc.getPrefs(user.id);
  if (!prefs.enabled) return 0;
  const { financeOwnerId } = require("../../middleware/access");
  const ledger = await financeOwnerId(user);
  const open = (await db.query(
    `SELECT (EXISTS (SELECT 1 FROM payment_schedule WHERE owner_id = $1 AND status = 'bekliyor')
          OR EXISTS (SELECT 1 FROM invoices WHERE owner_id = $1 AND direction = 'giden' AND status IN ('kesildi','gonderildi') AND due_date IS NOT NULL)) AS has`, [ledger])).rows[0].has;
  if (!open) return 0;
  const runAt = clock.zonedToUtc(today, prefs.morning_time || "07:30", prefs.tz);
  const expiresAt = new Date(runAt.getTime() + RECV_EXPIRE_AFTER_MS);
  if (expiresAt <= now) return 0;
  const r = await queue.enqueue("receivable.remind", { userId: user.id, date: today }, {
    runAt, expiresAt, userId: user.id, orgId: user.org_id, dedupeKey: `receivable.remind:${user.id}:${today}`, maxAttempts: 3,
  });
  return r.deduped ? 0 : 1;
}

/** Tüm uygun kullanıcılar için planla (tek lider: advisory lock). {leader, users, taxJobs, receivableJobs} */
async function planAll() {
  const now = clock.now();
  const today = clock.istanbulDateStr(now);
  const client = await db.pool.connect();
  let got = false;
  try {
    const lock = await client.query("SELECT pg_try_advisory_lock(hashtext('assistant.tax_plan')) AS ok");
    got = lock.rows[0].ok;
    if (!got) return { leader: false, users: 0, taxJobs: 0, receivableJobs: 0 };
    const { rows: users } = await db.query("SELECT id, org_id, role FROM users WHERE role = ANY($1::text[])", [ELIGIBLE_ROLES]);
    const cache = new Map();
    const out = { leader: true, users: 0, taxJobs: 0, receivableJobs: 0 };
    for (const u of users) {
      if (!cache.has(u.org_id)) cache.set(u.org_id, await loadOrgCalendar(u.org_id, today));
      out.users++;
      out.taxJobs += await planUserTax(u, cache.get(u.org_id), today, now);
      out.receivableJobs += await planUserReceivables(u, today, now);
    }
    return out;
  } finally {
    if (got) await client.query("SELECT pg_advisory_unlock(hashtext('assistant.tax_plan'))").catch(() => {});
    client.release();
  }
}

/** Ertesi gün 03:45 (İstanbul) için bir sonraki 'tax.plan' (zincir) */
async function scheduleNextPlan() {
  const now = clock.now();
  const tomorrow = addDays(clock.istanbulDateStr(now), 1);
  return queue.enqueue("tax.plan", {}, { runAt: clock.zonedToUtc(tomorrow, "03:45"), expiresAt: new Date(clock.zonedToUtc(tomorrow, "03:45").getTime() + 20 * 3600 * 1000), dedupeKey: `tax.plan:${tomorrow}`, maxAttempts: 3 });
}

/**
 * Zinciri başlat/yenile (idempotent, hatayı yutar: API isteğini asla bozmaz). force=true → takvim/statü değişti: aynı gün yeniden planla.
 * @returns {Promise<{id, deduped}|null>}
 */
async function bootstrap({ force = false } = {}) {
  try {
    const now = clock.now();
    const today = clock.istanbulDateStr(now);
    if (!force && lastBootstrapDay === today) return null;
    const key = force ? `tax.plan:${today}:${Math.floor(now.getTime() / 600000)}` : `tax.plan:${today}`;
    const r = await queue.enqueue("tax.plan", {}, { runAt: now, expiresAt: new Date(now.getTime() + 6 * 3600 * 1000), dedupeKey: key, maxAttempts: 3 });
    lastBootstrapDay = today;
    return r;
  } catch (e) { console.error("[tax] bootstrap hatası:", e.message); return null; }
}
const _resetBootstrap = () => { lastBootstrapDay = null; };

module.exports = { ELIGIBLE_ROLES, OFFSETS, HORIZON_DAYS, planAll, scheduleNextPlan, bootstrap, occurrencesFor, loadOrgCalendar, _resetBootstrap };
