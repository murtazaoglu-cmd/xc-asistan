const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const { financeOwnerId } = require("../middleware/access");
const { scopeClause } = require("../middleware/ownership");
const { financeSummary } = require("../services/finance");

const router = express.Router();

/** Aylık ciro trendi: GET /api/reports/revenue?range=monthly|yearly — yalnızca kullanıcının kendi defteri */
router.get("/revenue", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const range = req.query.range === "yearly" ? "year" : "month";
  const fmt = range === "year" ? "YYYY" : "YYYY-MM";
  const { rows } = await db.query(`
    SELECT to_char(date_trunc('${range}', paid_at AT TIME ZONE 'Europe/Istanbul'), '${fmt}') AS period,
           SUM(amount)::float8 AS total
    FROM payments
    WHERE owner_id = $1
    GROUP BY 1 ORDER BY 1
  `, [await financeOwnerId(req.user)]);
  res.json(rows);
});

/**
 * Dönemsel kâr raporu: GET /api/reports/profit?range=monthly|yearly
 * "ev" (kişisel) giderler işletme net kârına DAHİL DEĞİLDİR; ayrı alan olarak döner:
 *   [{ period, revenue, businessExpenses, homeExpenses, netProfit, netProfitInclHome }]
 *   netProfit = revenue − businessExpenses (dükkan + genel);  netProfitInclHome = netProfit − homeExpenses
 * Yalnızca kullanıcının kendi defteri (revenue endpoint'i ile aynı kapsam).
 */
router.get("/profit", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const range = req.query.range === "yearly" ? "year" : "month";
  const fmt = range === "year" ? "YYYY" : "YYYY-MM";
  const { rows } = await db.query(`
    WITH r AS (
      SELECT to_char(date_trunc('${range}', paid_at AT TIME ZONE 'Europe/Istanbul'), '${fmt}') AS period, SUM(amount) AS v
      FROM payments WHERE owner_id = $1 GROUP BY 1
    ), e AS (
      SELECT to_char(date_trunc('${range}', expense_date AT TIME ZONE 'Europe/Istanbul'), '${fmt}') AS period,
             SUM(amount) FILTER (WHERE scope <> 'ev') AS biz, SUM(amount) FILTER (WHERE scope = 'ev') AS home
      FROM expenses WHERE owner_id = $1 GROUP BY 1
    )
    SELECT COALESCE(r.period, e.period) AS period,
           COALESCE(r.v, 0)::float8 AS revenue,
           COALESCE(e.biz, 0)::float8 AS "businessExpenses",
           COALESCE(e.home, 0)::float8 AS "homeExpenses"
    FROM r FULL JOIN e ON e.period = r.period ORDER BY 1
  `, [await financeOwnerId(req.user)]);
  const r2 = (n) => Math.round(n * 100) / 100;
  res.json(rows.map((x) => ({
    ...x,
    netProfit: r2(x.revenue - x.businessExpenses),
    netProfitInclHome: r2(x.revenue - x.businessExpenses - x.homeExpenses),
  })));
});

/** Hizmet bazlı teklif dağılımı — yalnızca erişilebilen teklifler */
router.get("/service-distribution", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const scope = scopeClause(req.user, "o", "offer", 1);
  const { rows } = await db.query(
    `SELECT o.service, COUNT(*)::int AS count FROM offers o WHERE 1=1 ${scope.clause} GROUP BY o.service ORDER BY count DESC`,
    scope.params
  );
  res.json(rows);
});

/** Genel özet: dönüşüm oranı, toplam ciro, aktif proje sayısı */
router.get("/summary", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const offerScope = scopeClause(req.user, "o", "offer", 1);
  const projectScope = scopeClause(req.user, "p", "project", 1);
  const [offers, revenue, activeProjects, fin] = await Promise.all([
    db.query(`SELECT o.status, COUNT(*) FROM offers o WHERE 1=1 ${offerScope.clause} GROUP BY o.status`, offerScope.params),
    db.query("SELECT COALESCE(SUM(amount),0) AS total FROM payments WHERE owner_id = $1", [await financeOwnerId(req.user)]),
    db.query(`SELECT COUNT(*) FROM projects p WHERE p.stage != 'Tamamlandı' ${projectScope.clause}`, projectScope.params),
    financeOwnerId(req.user).then((id) => financeSummary(id)),
  ]);

  const statusCounts = {};
  offers.rows.forEach((r) => { statusCounts[r.status] = Number(r.count); });
  const totalOffers = Object.values(statusCounts).reduce((a, b) => a + b, 0);
  const accepted = statusCounts["Kabul Edildi"] || 0;

  res.json({
    totalOffers,
    statusCounts,
    conversionRate: totalOffers > 0 ? Math.round((accepted / totalOffers) * 100) : 0,
    totalRevenue: Number(revenue.rows[0].total),
    activeProjects: Number(activeProjects.rows[0].count),
    // Yeni (eklemeli) alanlar — "ev" giderleri işletme net kârına dahil değildir
    businessExpenses: fin.businessExpenses,
    homeExpenses: fin.homeExpenses,
    expensesByScope: fin.expensesByScope,
    netProfit: fin.netProfit,
    netProfitInclHome: fin.netProfitInclHome,
  });
});

module.exports = router;
