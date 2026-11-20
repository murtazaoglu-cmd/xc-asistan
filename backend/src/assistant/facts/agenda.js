/**
 * Gün gündemi (Sekreter): randevular, hatırlatmalar, yeni talepler, geciken işler, cevapsız (sonuçsuz) geçmiş randevular.
 * Kapsam: context.js (saha/personel yalnız kendi atanmış kayıtları; saha finans/tutar görmez — burada zaten tutar YOK).
 */
const db = require("../../db");
const clock = require("../clock");
const tr = require("../text/tr");
const { APPT_SELECT } = require("../../services/appointmentQueries");
const { params, ownerClause, apptClause, apptState } = require("./context");

function mapAppt(a, tz) {
  return {
    id: a.id, scheduled_at: new Date(a.scheduled_at).toISOString(), time: tr.formatTime(a.scheduled_at, tz), date: clock.zonedDateStr(a.scheduled_at, tz),
    type: a.type, status: a.status, state: apptState(a.status),
    customer_name: a.customer_name || null, customer_phone: a.customer_phone || null, address: a.address || null,
    lat: a.lat == null ? null : Number(a.lat), lng: a.lng == null ? null : Number(a.lng), service: a.service || null, notes: a.notes || null,
    offer_id: a.offer_id || null, project_id: a.project_id || null, assigned_user_id: a.assigned_user_id || null, owner_id: a.owner_id || null,
  };
}

/** [from,to) aralığındaki iptal olmayan randevular (saate göre) */
async function appointmentsBetween(ctx, from, to, { includeCancelled = false, onlyOpen = false, mode = "ops", limit = 200 } = {}) {
  const p = params([from, to, ctx.orgId]);
  let where = `a.scheduled_at >= $1 AND a.scheduled_at < $2 AND a.org_id = $3`;
  if (!includeCancelled) where += ` AND lower(coalesce(a.status,'')) NOT LIKE 'iptal%'`;
  if (onlyOpen) where += ` AND lower(coalesce(a.status,'')) NOT LIKE 'iptal%' AND lower(coalesce(a.status,'')) NOT LIKE 'tamamlan%' AND lower(coalesce(a.status,'')) NOT LIKE 'ertelen%'`;
  where += apptClause(ctx, p, mode);
  const { rows } = await db.query(`${APPT_SELECT} WHERE ${where} ORDER BY a.scheduled_at ASC LIMIT ${Number(limit)}`, p.arr);
  return rows.map((r) => mapAppt(r, ctx.tz));
}

async function appointmentsOn(ctx, dateStr = ctx.date, opts = {}) {
  const start = clock.zonedToUtc(dateStr, "00:00", ctx.tz), end = clock.zonedToUtc(clock.addDays(dateStr, 1), "00:00", ctx.tz);
  return appointmentsBetween(ctx, start, end, opts);
}

/** Geçmişte kalmış ama sonucu işlenmemiş (planlı/beklemede) randevular — son `days` gün */
async function pastOpenAppointments(ctx, days = 14) {
  const from = clock.zonedToUtc(clock.addDays(ctx.date, -days), "00:00", ctx.tz);
  return appointmentsBetween(ctx, from, ctx.dayStart, { onlyOpen: true });
}

/** Kullanıcının kendi hatırlatmaları (alıcı = owner_id): bugün (vadesi bugün biten) + geciken. Yalnız bekleyenler. */
async function remindersFor(ctx) {
  const { rows } = await db.query(
    `SELECT r.id, r.title, r.remind_at, r.note, r.project_id, r.source, r.recurrence, r.snooze_count, p.customer_name, p.code AS project_code
       FROM reminders r LEFT JOIN projects p ON p.id = r.project_id
      WHERE r.owner_id = $1 AND r.status = 'bekliyor' AND r.remind_at < $2 AND r.org_id = $3
      ORDER BY r.remind_at ASC LIMIT 60`, [ctx.userId, ctx.dayEnd, ctx.orgId]);
  const map = (r) => ({ id: r.id, title: r.title, remind_at: new Date(r.remind_at).toISOString(), time: tr.formatTime(r.remind_at, ctx.tz), date: clock.zonedDateStr(r.remind_at, ctx.tz), note: r.note, project_id: r.project_id, project_code: r.project_code, customer_name: r.customer_name, source: r.source, recurrence: r.recurrence, snooze_count: r.snooze_count });
  const all = rows.map(map);
  return { today: all.filter((r) => new Date(r.remind_at) >= ctx.dayStart), overdue: all.filter((r) => new Date(r.remind_at) < ctx.dayStart) };
}

/** Durumu "Yeni" olan (henüz ele alınmamış) talepler. saha: yok. */
async function newRequests(ctx, { mode = "ops" } = {}) {
  if (ctx.isField) return { count: 0, oldest_age_hours: 0, items: [] };
  const p = params([ctx.orgId, ctx.dayEnd]);
  const where = `o.status = 'Yeni' AND o.org_id = $1 AND o.created_at < $2` + ownerClause(ctx, "o", "offer", p, mode);
  const { rows } = await db.query(
    `SELECT o.id, o.code, o.name, o.phone, o.service, o.region, o.created_at, COUNT(*) OVER ()::int AS total
       FROM offers o WHERE ${where} ORDER BY o.created_at ASC LIMIT 20`, p.arr);
  const refEnd = ctx.dayEnd.getTime() < ctx.now.getTime() ? ctx.dayEnd : ctx.now;
  const items = rows.map((r) => ({ id: r.id, code: r.code, customer_name: r.name, phone: r.phone, service: r.service, region: r.region, created_at: new Date(r.created_at).toISOString(), age_hours: Math.max(0, Math.floor((refEnd - new Date(r.created_at)) / 3600000)) }));
  return { count: rows[0] ? rows[0].total : 0, oldest_age_hours: items[0] ? items[0].age_hours : 0, items: items.slice(0, 5) };
}

/** Planlanan teslim (end_date) geçmiş, aşama ≠ Tamamlandı. Tutar alanı YOK (saha güvenli). */
async function overdueJobs(ctx, { mode = "ops" } = {}) {
  const p = params([ctx.orgId, ctx.dayStart]);
  const where = `p.end_date IS NOT NULL AND p.end_date < $2 AND p.stage <> 'Tamamlandı' AND p.org_id = $1` + ownerClause(ctx, "p", "project", p, mode);
  const { rows } = await db.query(
    `SELECT p.id, p.code, p.customer_name, p.service, p.stage, p.end_date,
            ($${p.arr.length + 1}::date - (p.end_date AT TIME ZONE 'Europe/Istanbul')::date) AS days_overdue, COUNT(*) OVER ()::int AS total
       FROM projects p WHERE ${where} ORDER BY p.end_date ASC LIMIT 20`, [...p.arr, ctx.date]);
  return { count: rows[0] ? rows[0].total : 0, items: rows.slice(0, 10).map((r) => ({ id: r.id, code: r.code, customer_name: r.customer_name, service: r.service, stage: r.stage, end_date: clock.zonedDateStr(r.end_date, ctx.tz), days_overdue: r.days_overdue })) };
}

async function dayAgenda(ctx) {
  const [appointments, tomorrow, reminders, requests, overdue, pastOpen] = await Promise.all([
    appointmentsOn(ctx),
    appointmentsOn(ctx, clock.addDays(ctx.date, 1)),
    remindersFor(ctx),
    newRequests(ctx),
    overdueJobs(ctx),
    pastOpenAppointments(ctx),
  ]);
  return { date: ctx.date, appointments, tomorrow_count: tomorrow.length, tomorrow, reminders, new_requests: requests, overdue_jobs: overdue, past_open_appointments: pastOpen };
}

module.exports = { appointmentsBetween, appointmentsOn, pastOpenAppointments, remindersFor, newRequests, overdueJobs, dayAgenda, mapAppt };
