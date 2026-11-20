/** Düşük stok (stock_quantity <= low_stock_threshold). Kapsam mobil ana ekranla aynı: admin/muhasebe hepsi, ortak kendi, personel ekip liderinin; saha yok. */
const db = require("../../db");

async function lowStock(ctx, { limit = 20 } = {}) {
  if (ctx.isField) return { count: 0, items: [] };
  const { rows } = await db.query(
    `SELECT m.id, m.name, m.unit, m.stock_quantity::float8 AS stock, m.low_stock_threshold::float8 AS threshold, COUNT(*) OVER ()::int AS total
       FROM materials m
      WHERE m.stock_quantity <= m.low_stock_threshold AND m.org_id = $3
        AND ($2 = 'admin' OR $2 = 'muhasebe'
             OR m.owner_id = (CASE WHEN $2 = 'ortak' THEN $1::uuid ELSE (SELECT created_by FROM users WHERE id = $1::uuid) END))
      ORDER BY (m.stock_quantity - m.low_stock_threshold) ASC, m.name ASC LIMIT ${Number(limit)}`, [ctx.userId, ctx.role, ctx.orgId]);
  return { count: rows[0] ? rows[0].total : 0, items: rows.map((r) => ({ id: r.id, name: r.name, unit: r.unit, stock: r.stock, threshold: r.threshold })) };
}
module.exports = { lowStock };
