const express = require("express");
const db = require("../db");
const { requireAuth } = require("../middleware/auth");
const { scopeClause } = require("../middleware/ownership");
const { financeOwnerId } = require("../middleware/access");
const { listAppointments } = require("../services/appointmentQueries");

const router = express.Router();

/**
 * GET /api/mobile/home — mobil ana ekran: TEK istek, role göre kapsamlı, sorgular paralel (Promise.all).
 *
 * Kapsam: admin/muhasebe tümü; ortak/personel kendi + paylaşılan; saha yalnız kendine atanan/paylaşılan.
 * Teklif bölümleri saha için null. finance yalnız admin/muhasebe/ortak için (kendi defteri), diğerlerinde null.
 * Gün sınırları İstanbul saatine göre (db.js oturum saat dilimi).
 */
router.get("/home", requireAuth, async (req, res) => {
  const u = req.user;
  const isGlobal = u.role === "admin" || u.role === "muhasebe";
  const hasOffers = u.role !== "saha";
  const hasFinance = isGlobal || u.role === "ortak";

  const ledger = hasFinance ? await financeOwnerId(u) : null;
  const offerScope = scopeClause(u, "o", "offer", 1);
  const projectScope = scopeClause(u, "p", "project", 1);

  const queries = {
    // Bugün + yarın (iptal edilenler hariç)
    appts: listAppointments(u, {
      extraWhere: [
        "a.scheduled_at >= date_trunc('day', now())",
        "a.scheduled_at < date_trunc('day', now()) + interval '2 days'",
        "lower(coalesce(a.status,'')) NOT LIKE 'iptal%'",
      ],
      limit: 100,
    }),
    offerCounts: hasOffers
      ? db.query(`SELECT o.status, COUNT(*)::int AS n FROM offers o WHERE 1=1 ${offerScope.clause} GROUP BY o.status`, offerScope.params)
      : null,
    newOffers: hasOffers
      ? db.query(`
          SELECT o.id, o.code, o.name, o.phone, o.service, o.region, o.address, o.status, o.created_at
          FROM offers o WHERE o.status = 'Yeni' ${offerScope.clause} ORDER BY o.created_at DESC LIMIT 5`, offerScope.params)
      : null,
    overdue: db.query(`
      SELECT p.id, p.code, p.customer_name, p.service, p.stage, p.end_date, p.address,
             ((now() AT TIME ZONE 'Europe/Istanbul')::date - (p.end_date AT TIME ZONE 'Europe/Istanbul')::date) AS days_overdue,
             COUNT(*) OVER ()::int AS total
      FROM projects p
      WHERE p.end_date IS NOT NULL AND p.end_date < date_trunc('day', now()) AND p.stage <> 'Tamamlandı' ${projectScope.clause}
      ORDER BY p.end_date ASC LIMIT 10`, projectScope.params),
    reminders: db.query(`
      SELECT r.id, r.title, r.remind_at, r.note, r.status, r.project_id, p.customer_name, p.code AS project_code,
             (r.remind_at < date_trunc('day', now())) AS overdue
      FROM reminders r LEFT JOIN projects p ON p.id = r.project_id
      WHERE r.status = 'bekliyor' AND r.remind_at < date_trunc('day', now()) + interval '1 day'
        AND ($2::boolean OR r.owner_id = $1
             OR (p.id IS NOT NULL AND (p.owner_id = $1 OR p.id IN (
                  SELECT resource_id FROM resource_shares WHERE resource_type = 'project' AND shared_with_user_id = $1))))
      ORDER BY r.remind_at ASC LIMIT 50`, [u.id, isGlobal]),
    // Stok: admin/muhasebe hepsi; ortak kendi; personel/saha ekip liderinin (kendilerini oluşturan) stoğu
    lowStock: db.query(`
      SELECT m.id, m.name, m.unit, m.stock_quantity, m.low_stock_threshold AS min_stock, m.low_stock_threshold,
             COUNT(*) OVER ()::int AS total
      FROM materials m
      WHERE m.stock_quantity <= m.low_stock_threshold
        AND ($2 = 'admin' OR $2 = 'muhasebe'
             OR m.owner_id = (CASE WHEN $2 = 'ortak' THEN $1::uuid ELSE (SELECT created_by FROM users WHERE id = $1::uuid) END))
      ORDER BY (m.stock_quantity - m.low_stock_threshold) ASC, m.name ASC LIMIT 20`, [u.id, u.role]),
  };

  if (hasFinance) {
    // Alacak: sözleşme + ilave işler − kendi defterindeki tahsilat. admin/muhasebe işletme (admin/muhasebe sahipli
    // ya da sahipsiz) projeleri; ortak yalnız kendi sahibi olduğu projeleri hesaplar (başka ortağın verisi karışmaz).
    const ownerFilter = u.role === "ortak"
      ? "p.owner_id = $2"
      : "(p.owner_id IS NULL OR p.owner_id IN (SELECT id FROM users WHERE role IN ('admin','muhasebe')))";
    queries.collected = db.query(`
      SELECT
        COALESCE(SUM(amount) FILTER (WHERE paid_at >= date_trunc('week', now())  AND paid_at < date_trunc('week', now())  + interval '1 week'), 0)::float8 AS week,
        COALESCE(SUM(amount) FILTER (WHERE paid_at >= date_trunc('month', now()) AND paid_at < date_trunc('month', now()) + interval '1 month'), 0)::float8 AS month
      FROM payments
      WHERE owner_id = $1 AND paid_at >= LEAST(date_trunc('week', now()), date_trunc('month', now()))`, [ledger]);
    queries.receivable = db.query(`
      SELECT id, code, customer_name, balance,
             SUM(balance) OVER ()::float8 AS total, COUNT(*) OVER ()::int AS cnt
      FROM (
        SELECT p.id, p.code, p.customer_name,
               (p.total_amount + COALESCE(ex.s, 0) - COALESCE(pay.s, 0))::float8 AS balance
        FROM projects p
        LEFT JOIN (SELECT project_id, SUM(amount) AS s FROM payments WHERE owner_id = $1 GROUP BY project_id) pay ON pay.project_id = p.id
        LEFT JOIN (SELECT project_id, SUM(amount) AS s FROM project_extras GROUP BY project_id) ex ON ex.project_id = p.id
        WHERE ${ownerFilter}
      ) b WHERE balance > 0 ORDER BY balance DESC LIMIT 5`,
      u.role === "ortak" ? [ledger, u.id] : [ledger]);
  }

  const keys = Object.keys(queries);
  const results = await Promise.all(keys.map((k) => queries[k]));
  const r = Object.fromEntries(keys.map((k, i) => [k, results[i]]));

  // Randevular: bugün / yarın ayrımı İstanbul takvim gününe göre
  const dayOf = (d) => new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Istanbul" }).format(new Date(d));
  const todayStr = dayOf(Date.now());
  const tomorrowStr = dayOf(Date.now() + 24 * 3600 * 1000);
  const appointments = { today: [], tomorrow: [] };
  r.appts.forEach((a) => {
    const d = dayOf(a.scheduled_at);
    if (d === todayStr) appointments.today.push(a);
    else if (d === tomorrowStr) appointments.tomorrow.push(a);
  });

  let offerStats = null, newOffers = null;
  if (hasOffers) {
    const by = {};
    r.offerCounts.rows.forEach((x) => { by[x.status] = x.n; });
    const n = (k) => by[k] || 0;
    newOffers = { count: n("Yeni"), latest: r.newOffers.rows };
    offerStats = {
      awaitingQuote: n("Yeni") + n("İncelendi") + n("Keşif Planlandı"), // teklif hazırlanmayı bekleyen
      awaitingResponse: n("Teklif Verildi"),                           // müşteri kararını bekleyen
      accepted: n("Kabul Edildi"),
      rejected: n("Reddedildi"),
      byStatus: by,
    };
  }

  let finance = null;
  if (hasFinance) {
    const rec = r.receivable.rows;
    finance = {
      collectedThisWeek: r.collected.rows[0].week,
      collectedThisMonth: r.collected.rows[0].month,
      receivableTotal: rec.length ? Math.round(rec[0].total * 100) / 100 : 0,
      receivableProjectCount: rec.length ? rec[0].cnt : 0,
      topReceivables: rec.map((x) => ({ id: x.id, code: x.code, customer_name: x.customer_name, balance: x.balance })),
    };
  }

  const odRows = r.overdue.rows.map(({ total, ...rest }) => rest);
  const lsRows = r.lowStock.rows.map(({ total, ...rest }) => rest);
  res.json({
    generatedAt: new Date().toISOString(),
    user: { id: u.id, name: u.name, role: u.role },
    appointments,
    newOffers,
    offerStats,
    overdueProjects: { count: r.overdue.rows[0]?.total || 0, items: odRows },
    finance,
    reminders: {
      today: r.reminders.rows.filter((x) => !x.overdue),
      overdue: r.reminders.rows.filter((x) => x.overdue),
    },
    lowStock: { count: r.lowStock.rows[0]?.total || 0, items: lsRows },
  });
});

module.exports = router;
