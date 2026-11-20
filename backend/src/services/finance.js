const db = require("../db");

/**
 * Bir defterin (owner_id) finans özeti. "ev" (kişisel) giderler işletme net kârına DAHİL EDİLMEZ:
 *   netProfit          = tahsilat − (dükkan + genel giderler)      ← işletme net kârı
 *   homeExpenses       = scope 'ev' giderleri (ayrı raporlanır)
 *   netProfitInclHome  = tahsilat − tüm giderler (eski "hepsi" görünümü)
 * range: {from, to} (ISO, opsiyonel) — her ikisi de dahil/hariç olmayan sınır: from ≤ tarih < to
 */
async function financeSummary(ledgerOwnerId, range = {}) {
  const params = [ledgerOwnerId];
  let payWhere = "owner_id = $1", expWhere = "owner_id = $1";
  if (range.from) { params.push(range.from); payWhere += ` AND paid_at >= $${params.length}`; expWhere += ` AND expense_date >= $${params.length}`; }
  if (range.to) { params.push(range.to); payWhere += ` AND paid_at < $${params.length}`; expWhere += ` AND expense_date < $${params.length}`; }
  const [rev, exp] = await Promise.all([
    db.query(`SELECT COALESCE(SUM(amount),0)::float8 AS total FROM payments WHERE ${payWhere}`, params),
    db.query(`SELECT scope, COALESCE(SUM(amount),0)::float8 AS total FROM expenses WHERE ${expWhere} GROUP BY scope`, params),
  ]);
  const by = { dukkan: 0, genel: 0, ev: 0 };
  exp.rows.forEach((r) => { by[r.scope] = r.total; });
  const r2 = (n) => Math.round(n * 100) / 100;
  const totalRevenue = rev.rows[0].total;
  const businessExpenses = r2(by.dukkan + by.genel);
  const homeExpenses = r2(by.ev);
  return {
    totalRevenue: r2(totalRevenue),
    businessExpenses,
    homeExpenses,
    expensesByScope: { dukkan: r2(by.dukkan), genel: r2(by.genel), ev: homeExpenses },
    netProfit: r2(totalRevenue - businessExpenses),
    netProfitInclHome: r2(totalRevenue - businessExpenses - homeExpenses),
  };
}

module.exports = { financeSummary };
