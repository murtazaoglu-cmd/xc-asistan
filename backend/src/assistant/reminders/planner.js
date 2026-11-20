/**
 * Hatırlatma/ek iş planlayıcı (plan_day işleyicisi her ~10 dk'da çağırır; hepsi idempotent — dedupeKey):
 *  - randevu öncesi: önceki akşam 18:00 ("yarın N randevu", kullanıcı başına gün başına TEK) + 60 dk önce (randevu başına)
 *  - bekleyen hatırlatmalar için güvenlik ağı (yeni/ertelenen hatırlatma işi kaçmışsa)
 *  - haftalık (Pzt) / aylık (ayın 1'i) müdür raporu işleri: yalnız admin/muhasebe/ortak, sabah saatinin 10 dk sonrasına
 */
const db = require("../../db");
const clock = require("../clock");
const queue = require("../queue");
const prefsSvc = require("../prefs");
const svc = require("./service");

const EVE_TIME = "18:00";
const EVE_GRACE_MS = 3 * 3600 * 1000;
const HOUR_BEFORE_MS = 60 * 60000;
const MANAGER_ROLES = ["admin", "muhasebe", "ortak"];

async function planAppointmentReminders(now = clock.now()) {
  const out = { eve: 0, hour: 0 };
  const { rows } = await db.query(
    `SELECT a.id, a.scheduled_at, a.assigned_user_id, a.owner_id, a.org_id FROM appointments a
      WHERE a.scheduled_at >= $1 AND a.scheduled_at < $2 AND lower(coalesce(a.status,'')) NOT LIKE 'iptal%' AND lower(coalesce(a.status,'')) NOT LIKE 'tamamlan%'`,
    [now, new Date(now.getTime() + 48 * 3600000)]);
  const today = clock.istanbulDateStr(now);
  const eveSeen = new Set();
  for (const a of rows) {
    const at = new Date(a.scheduled_at);
    const date = clock.istanbulDateStr(at);
    const users = [...new Set([a.assigned_user_id, a.owner_id].filter(Boolean))];
    for (const u of users) {
      // 60 dk önce
      let runAt = new Date(at.getTime() - HOUR_BEFORE_MS);
      if (runAt < now) runAt = at.getTime() - now.getTime() > 10 * 60000 ? now : null;
      if (runAt) {
        const r = await queue.enqueue("reminder.fire", { kind: "appointment_hour", appointmentId: a.id, scheduledAt: at.toISOString(), userId: u }, {
          runAt, userId: u, orgId: a.org_id || undefined, dedupeKey: `reminder.fire:appt60:${a.id}:${Math.floor(at.getTime() / 1000)}:${u}`, expiresAt: at, maxAttempts: 3 });
        if (!r.deduped) out.hour++;
      }
      // önceki akşam (yalnız yarın ve sonrası için; bugünkü randevuları sabah brifingi karşılar)
      if (date > today) {
        const k = `${u}:${date}`;
        if (eveSeen.has(k)) continue;
        eveSeen.add(k);
        const eveAt = clock.zonedToUtc(clock.addDays(date, -1), EVE_TIME);
        if (eveAt.getTime() + EVE_GRACE_MS <= now.getTime()) continue;
        const r = await queue.enqueue("reminder.fire", { kind: "appointment_eve", userId: u, date }, {
          runAt: eveAt < now ? now : eveAt, userId: u, orgId: a.org_id || undefined, dedupeKey: `reminder.fire:appt_eve:${u}:${date}`, expiresAt: new Date(eveAt.getTime() + EVE_GRACE_MS), maxAttempts: 3 });
        if (!r.deduped) out.eve++;
      }
    }
  }
  return out;
}

async function planPendingReminders(now = clock.now()) {
  const { rows } = await db.query(
    `SELECT * FROM reminders WHERE status = 'bekliyor' AND owner_id IS NOT NULL AND remind_at < $2 AND remind_at > $1 AND fired_at IS NULL`,
    [new Date(now.getTime() - svc.FIRE_GRACE_MS), new Date(now.getTime() + 24 * 3600000)]);
  let n = 0;
  for (const r of rows) { const x = await svc.schedule(r); if (x && !x.deduped) n++; }
  return { scheduled: n };
}

/** Haftalık (Pzt) / aylık (ayın 1'i) rapor işleri: kullanıcının sabah saatinden 10 dk sonra; yalnız yönetici roller */
async function planManagerReports(now = clock.now()) {
  const out = { weekly: 0, monthly: 0 };
  const { rows } = await db.query(`SELECT u.id AS uid, u.org_id AS uorg, u.role AS urole, np.* FROM users u LEFT JOIN notification_prefs np ON np.user_id = u.id WHERE u.role = ANY($1)`, [MANAGER_ROLES]);
  const cache = new Map();
  for (const r of rows) {
    const org = cache.get(r.uorg) || (await prefsSvc.orgTimes(r.uorg));
    cache.set(r.uorg, org);
    const p = prefsSvc.effective(r.user_id ? r : null, org);
    if (!p.enabled || !p.morning_enabled) continue;
    const date = clock.zonedDateStr(now, p.tz);
    const dow = clock.zonedWeekday(now, p.tz);
    const base = clock.zonedToUtc(date, p.morning_time, p.tz);
    const runAt = new Date(base.getTime() + 10 * 60000);
    const expiresAt = new Date(base.getTime() + 3.5 * 3600000);
    if (expiresAt <= now) continue;
    const kinds = [];
    if (dow === 1) kinds.push(["briefing.weekly", "weekly"]);
    if (date.endsWith("-01")) kinds.push(["briefing.monthly", "monthly"]);
    for (const [job, kind] of kinds) {
      const res = await queue.enqueue(job, { userId: r.uid, date, kind }, { runAt, userId: r.uid, orgId: r.uorg || undefined, dedupeKey: `${job}:${r.uid}:${date}`, expiresAt, maxAttempts: 3 });
      if (!res.deduped) out[kind]++;
    }
  }
  return out;
}

async function planAll(now = clock.now()) {
  const a = await planAppointmentReminders(now);
  const b = await planPendingReminders(now);
  const c = await planManagerReports(now);
  return { appointments: a, reminders: b, reports: c };
}

module.exports = { planAll, planAppointmentReminders, planPendingReminders, planManagerReports, EVE_TIME };
