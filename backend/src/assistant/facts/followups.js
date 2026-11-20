/**
 * Açık takipler: (1) followups tablosu (kullanıcının "ara/teklif/tahsilat" takipleri; vadesi gelmiş), (2) türetilmiş: yanıt bekleyen teklifler (≥3 gün).
 * Yalnız çağıranın kendi takipleri; türetilmiş teklif takipleri çağıranın teklif kapsamındadır.
 */
const db = require("../../db");
const funnel = require("./funnel");

async function listFollowups(ctx, { status, limit = 100 } = {}) {
  const st = status === "all" ? null : status || "acik";
  const { rows } = await db.query(
    `SELECT f.*, to_char(f.due_date,'YYYY-MM-DD') AS due_ymd FROM followups f WHERE f.user_id = $1 AND f.org_id = $2 AND ($3::text IS NULL OR f.status = $3) ORDER BY f.due_date ASC, f.created_at ASC LIMIT ${Number(limit)}`,
    [ctx.userId, ctx.orgId, st]);
  return rows.map(({ due_ymd, ...r }) => ({ ...r, due_date: due_ymd }));
}

async function openFollowups(ctx, { horizonDays = 0 } = {}) {
  const { rows } = await db.query(
    `SELECT f.id, f.kind, f.title, to_char(f.due_date,'YYYY-MM-DD') AS due_ymd, f.customer_name, f.customer_phone, f.offer_id, f.project_id, f.source,
            ($3::date - f.due_date) AS overdue_days
       FROM followups f
      WHERE f.user_id = $1 AND f.org_id = $2 AND f.status IN ('acik','ertelendi')
        AND f.due_date <= ($3::date + $4::int) AND (f.snoozed_until IS NULL OR f.snoozed_until <= $3::date)
      ORDER BY f.due_date ASC, f.created_at ASC LIMIT 50`, [ctx.userId, ctx.orgId, ctx.date, horizonDays]);
  const own = rows.map((r) => ({ type: "followup", id: r.id, kind: r.kind, title: r.title, due_date: r.due_ymd, customer_name: r.customer_name, customer_phone: r.customer_phone, offer_id: r.offer_id, project_id: r.project_id, overdue_days: Math.max(0, r.overdue_days), source: r.source }));
  const waiting = ctx.isField ? { items: [] } : await funnel.waitingQuotes(ctx, { mode: "ops", minAgeDays: 3 });
  const derived = waiting.items.map((w) => ({ type: "quote_waiting", id: w.id, kind: "teklif", title: null, customer_name: w.customer_name, customer_phone: w.phone, offer_id: w.id, age_days: w.age_days, quote_total_kurus: w.quote_total_kurus }));
  return { count: own.length + derived.length, followups: own, quote_waiting: derived, due_count: own.length };
}

module.exports = { listFollowups, openFollowups };
