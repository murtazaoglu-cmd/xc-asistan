/**
 * Teklif hunisi: durum sayıları, yanıt bekleyen teklif yaşı, cevapsız talepler, keşif sonrası teklifsizler, dönüşüm (90/90 gün).
 * Para (teklif tutarı) yalnız canFinance rollere döner. Kapsam: ops (listeler) / biz (dönüşüm, boru hattı).
 */
const db = require("../../db");
const clock = require("../clock");
const { params, ownerClause } = require("./context");
const { workHoursBetween } = require("./timeutil");

const OPEN = ["Yeni", "İncelendi", "Keşif Planlandı", "Teklif Verildi"];

const LATEST_QUOTE = `LEFT JOIN LATERAL (SELECT q.created_at, ROUND(q.total*100)::bigint AS total_k FROM quotes q WHERE q.offer_id = o.id AND q.created_at < $2 ORDER BY q.created_at DESC LIMIT 1) q ON true`;

async function statusCounts(ctx, mode = "ops") {
  if (ctx.isField) return {};
  const p = params([ctx.orgId]);
  const { rows } = await db.query(`SELECT o.status, COUNT(*)::int AS n FROM offers o WHERE o.org_id = $1${ownerClause(ctx, "o", "offer", p, mode)} GROUP BY o.status`, p.arr);
  return Object.fromEntries(rows.map((r) => [r.status, r.n]));
}

/** Teklif verilmiş, yanıt bekleyenler: yaş = teklifin (son quote) verildiği günden bu yana gün */
async function waitingQuotes(ctx, { mode = "ops", minAgeDays = 0 } = {}) {
  if (ctx.isField) return { count: 0, items: [], total_kurus: ctx.canFinance ? 0 : null };
  const p = params([ctx.orgId, ctx.dayEnd]);
  const where = `o.status = 'Teklif Verildi' AND o.org_id = $1` + ownerClause(ctx, "o", "offer", p, mode);
  const dIdx = p.add(ctx.date);
  const { rows } = await db.query(
    `SELECT o.id, o.code, o.name, o.phone, o.service, o.source_site, q.total_k,
            COALESCE(q.created_at, o.status_changed_at, o.updated_at) AS since,
            (${dIdx}::date - (COALESCE(q.created_at, o.status_changed_at, o.updated_at) AT TIME ZONE 'Europe/Istanbul')::date) AS age_days
       FROM offers o ${LATEST_QUOTE} WHERE ${where} ORDER BY since ASC`, p.arr);
  const items = rows.map((r) => ({ id: r.id, code: r.code, customer_name: r.name, phone: r.phone, service: r.service, source_site: r.source_site, age_days: Math.max(0, r.age_days), quote_total_kurus: ctx.canFinance ? (r.total_k == null ? null : Number(r.total_k)) : null, since: new Date(r.since).toISOString() })).filter((x) => x.age_days >= minAgeDays);
  return { count: items.length, items, total_kurus: ctx.canFinance ? items.reduce((s, x) => s + (x.quote_total_kurus || 0), 0) : null };
}

/** Cevapsız (Yeni) talepler: iş saati yaşı + gerçek geçen saat */
async function unansweredRequests(ctx, { mode = "ops" } = {}) {
  if (ctx.isField) return { count: 0, items: [] };
  const p = params([ctx.orgId, ctx.dayEnd]);
  const { rows } = await db.query(
    `SELECT o.id, o.code, o.name, o.phone, o.service, o.created_at FROM offers o WHERE o.status = 'Yeni' AND o.org_id = $1 AND o.created_at < $2${ownerClause(ctx, "o", "offer", p, mode)} ORDER BY o.created_at ASC LIMIT 100`, p.arr);
  const ref = ctx.dayEnd.getTime() < ctx.now.getTime() ? ctx.dayEnd : ctx.now;
  const items = rows.map((r) => ({ id: r.id, code: r.code, customer_name: r.name, phone: r.phone, service: r.service, created_at: new Date(r.created_at).toISOString(), hours: (ref - new Date(r.created_at)) / 3600000, work_hours: workHoursBetween(r.created_at, ref, ctx.tz) }));
  return { count: items.length, items };
}

/** "Keşif Planlandı" + geçmiş randevu var + teklif yok */
async function visitWithoutQuote(ctx, { mode = "ops" } = {}) {
  if (ctx.isField) return { count: 0, items: [] };
  const p = params([ctx.orgId, ctx.dayStart]);
  const where = `o.status = 'Keşif Planlandı' AND o.org_id = $1 AND NOT EXISTS (SELECT 1 FROM quotes q WHERE q.offer_id = o.id)` + ownerClause(ctx, "o", "offer", p, mode);
  const dIdx = p.add(ctx.date);
  const { rows } = await db.query(
    `SELECT o.id, o.code, o.name, o.phone, o.service, v.last_at,
            (${dIdx}::date - (v.last_at AT TIME ZONE 'Europe/Istanbul')::date) AS age_days
       FROM offers o JOIN LATERAL (SELECT MAX(a.scheduled_at) AS last_at FROM appointments a
                                    WHERE a.offer_id = o.id AND a.scheduled_at < $2 AND lower(coalesce(a.status,'')) NOT LIKE 'iptal%') v ON v.last_at IS NOT NULL
      WHERE ${where} ORDER BY v.last_at ASC LIMIT 100`, p.arr);
  return { count: rows.length, items: rows.map((r) => ({ id: r.id, code: r.code, customer_name: r.name, phone: r.phone, service: r.service, last_visit_at: new Date(r.last_at).toISOString(), age_days: r.age_days })) };
}

/** Dönüşüm: kabul / (kabul + red + 30 günü geçip yanıtsız kalan); recent = son 90 gün, prev = önceki 90 gün (oluşturulma tarihine göre kohort) */
async function conversion(ctx, { mode = "biz", staleDays = 30 } = {}) {
  const recentFrom = clock.zonedToUtc(clock.addDays(ctx.date, -90), "00:00", ctx.tz);
  const prevFrom = clock.zonedToUtc(clock.addDays(ctx.date, -180), "00:00", ctx.tz);
  const staleBefore = new Date(ctx.dayEnd.getTime() - staleDays * 86400000);
  const p = params([ctx.orgId, ctx.dayEnd, recentFrom, prevFrom, staleBefore]);
  const own = ownerClause(ctx, "o", "offer", p, mode);
  const { rows } = await db.query(
    `SELECT o.service, COALESCE(o.source_site, 'bilinmiyor') AS source_site,
       COUNT(*) FILTER (WHERE o.created_at >= $3 AND o.status = 'Kabul Edildi')::int AS ra,
       COUNT(*) FILTER (WHERE o.created_at >= $3 AND o.status = 'Reddedildi')::int AS rr,
       COUNT(*) FILTER (WHERE o.created_at >= $3 AND o.status NOT IN ('Kabul Edildi','Reddedildi') AND o.created_at < $5)::int AS rs,
       COUNT(*) FILTER (WHERE o.created_at >= $4 AND o.created_at < $3 AND o.status = 'Kabul Edildi')::int AS pa,
       COUNT(*) FILTER (WHERE o.created_at >= $4 AND o.created_at < $3 AND o.status = 'Reddedildi')::int AS pr,
       COUNT(*) FILTER (WHERE o.created_at >= $4 AND o.created_at < $3 AND o.status NOT IN ('Kabul Edildi','Reddedildi') AND o.created_at < $5)::int AS ps
       FROM offers o WHERE o.org_id = $1 AND o.created_at < $2 AND o.created_at >= $4${own} GROUP BY 1, 2`, p.arr);
  const mk = (a, r, s) => { const res = a + r + s; return { accepted: a, rejected: r, stale: s, resolved: res, rate_bp: res > 0 ? Math.round((a * 10000) / res) : null }; };
  const sum = (k) => rows.reduce((t, x) => t + x[k], 0);
  const breakdown = (field) => {
    const m = new Map();
    for (const x of rows) {
      const key = x[field];
      const c = m.get(key) || { key, ra: 0, rr: 0, rs: 0, pa: 0, pr: 0, ps: 0 };
      for (const f of ["ra", "rr", "rs", "pa", "pr", "ps"]) c[f] += x[f];
      m.set(key, c);
    }
    return [...m.values()].map((c) => ({ key: c.key, recent: mk(c.ra, c.rr, c.rs), prev: mk(c.pa, c.pr, c.ps) }));
  };
  return { recent: mk(sum("ra"), sum("rr"), sum("rs")), prev: mk(sum("pa"), sum("pr"), sum("ps")), by_service: breakdown("service"), by_source: breakdown("source_site") };
}

async function openOfferCount(ctx, mode = "biz") {
  const p = params([ctx.orgId, OPEN]);
  const { rows } = await db.query(`SELECT COUNT(*)::int AS n FROM offers o WHERE o.org_id = $1 AND o.status = ANY($2)${ownerClause(ctx, "o", "offer", p, mode)}`, p.arr);
  return rows[0].n;
}

async function offerFunnel(ctx, { mode = "ops" } = {}) {
  const [by, waiting, unanswered, visit] = await Promise.all([statusCounts(ctx, mode), waitingQuotes(ctx, { mode }), unansweredRequests(ctx, { mode }), visitWithoutQuote(ctx, { mode })]);
  return { by_status: by, waiting_quotes: waiting, unanswered_requests: unanswered, visit_without_quote: visit };
}

module.exports = { OPEN, statusCounts, waitingQuotes, unansweredRequests, visitWithoutQuote, conversion, openOfferCount, offerFunnel };
