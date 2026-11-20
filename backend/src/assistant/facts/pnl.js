/**
 * Ay P&L ve gün/aralık para özeti. KURUŞ tamsayısı. scope='ev' (kişisel) işletme net kârına DAHİL DEĞİL (ayrı döner).
 *   net = tahsilat − (dukkan + genel giderler)
 * Defter: ctx.ledgerOwnerId (admin/muhasebe → işletme defteri; ortak → kendi). saha/personel → null (finans görmez).
 * Sabit giderler: aktif recurring_expenses (scope<>'ev') — o ay henüz uygulanmamış (recurring_expense_applications) olanların toplamı
 * "kalan sabit gider"dir; tahmini ay gideri = gerçekleşen + kalan sabit.
 */
const db = require("../../db");
const clock = require("../clock");
const { params } = require("./context");

/** [from, to) aralığı: tahsilat, işletme gideri (dukkan+genel), ev gideri, kategori kırılımı */
async function rangePnl(ctx, from, to) {
  if (!ctx.canFinance) return null;
  const [pay, exp] = await Promise.all([
    db.query(`SELECT COALESCE(SUM(ROUND(amount*100)),0)::bigint AS k, COUNT(*)::int AS n FROM payments WHERE owner_id = $1 AND org_id = $4 AND paid_at >= $2 AND paid_at < $3`, [ctx.ledgerOwnerId, from, to, ctx.orgId]),
    db.query(`SELECT scope, category, COALESCE(SUM(ROUND(amount*100)),0)::bigint AS k, COUNT(*)::int AS n FROM expenses WHERE owner_id = $1 AND org_id = $4 AND expense_date >= $2 AND expense_date < $3 GROUP BY scope, category`, [ctx.ledgerOwnerId, from, to, ctx.orgId]),
  ]);
  let biz = 0, home = 0, nExp = 0;
  const byCat = new Map();
  const byScope = { dukkan: 0, genel: 0, ev: 0 };
  for (const r of exp.rows) {
    const k = Number(r.k); nExp += r.n;
    byScope[r.scope] = (byScope[r.scope] || 0) + k;
    if (r.scope === "ev") { home += k; continue; }
    biz += k;
    byCat.set(r.category, (byCat.get(r.category) || 0) + k);
  }
  const collected = Number(pay.rows[0].k);
  return {
    from: from.toISOString(), to: to.toISOString(),
    collected_kurus: collected, payments_count: pay.rows[0].n,
    expense_kurus: biz, home_expense_kurus: home, expenses_count: nExp,
    net_kurus: collected - biz, net_incl_home_kurus: collected - biz - home,
    by_category: [...byCat.entries()].map(([category, kurus]) => ({ category, kurus })).sort((a, b) => b.kurus - a.kurus),
    by_scope: byScope,
  };
}

/** Uygulanmamış sabit giderlerin toplamı (o ay) */
async function pendingFixed(ctx, month) {
  const p = params([ctx.orgId, month]);
  let own = "";
  if (ctx.isGlobal) own = ` AND (re.created_by IS NULL OR re.created_by IN (SELECT id FROM users WHERE role IN ('admin','muhasebe')))`;
  else own = ` AND re.created_by = ${p.add(ctx.userId)}`;
  const { rows } = await db.query(
    `SELECT COALESCE(SUM(ROUND(re.amount*100)),0)::bigint AS k, COUNT(*)::int AS n FROM recurring_expenses re
      WHERE re.active AND re.scope <> 'ev' AND re.org_id = $1 AND NOT EXISTS (SELECT 1 FROM recurring_expense_applications a WHERE a.recurring_expense_id = re.id AND a.year_month = $2)${own}`, p.arr);
  return { kurus: Number(rows[0].k), count: rows[0].n };
}

/** Aylık toplam sabit gider (aktif, ev hariç) — "gelecek 60 gün sabit gider" için */
async function monthlyFixedTotal(ctx) {
  const p = params([ctx.orgId]);
  const own = ctx.isGlobal ? ` AND (re.created_by IS NULL OR re.created_by IN (SELECT id FROM users WHERE role IN ('admin','muhasebe')))` : ` AND re.created_by = ${p.add(ctx.userId)}`;
  const { rows } = await db.query(`SELECT COALESCE(SUM(ROUND(re.amount*100)),0)::bigint AS k FROM recurring_expenses re WHERE re.active AND re.scope <> 'ev' AND re.org_id = $1${own}`, p.arr);
  return Number(rows[0].k);
}

function monthOf(dateStr) { return dateStr.slice(0, 7); }
function monthBounds(month, tz) {
  const start = clock.zonedToUtc(`${month}-01`, "00:00", tz);
  const [y, m] = month.split("-").map(Number);
  const next = `${m === 12 ? y + 1 : y}-${String(m === 12 ? 1 : m + 1).padStart(2, "0")}-01`;
  return { start, next: clock.zonedToUtc(next, "00:00", tz), nextStr: next, days: new Date(Date.UTC(y, m, 0)).getUTCDate() };
}
const prevMonth = (month) => { const [y, m] = month.split("-").map(Number); return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, "0")}`; };

/**
 * Ay P&L. Bulunulan ay ise gün sonuna kadar (as-of), geçmiş ay ise ayın tamamı.
 * {month, day_of_month, days_in_month, collected_kurus, expense_kurus, home_expense_kurus, net_kurus, fixed_pending_kurus, projected_expense_kurus, by_category[], by_scope}
 */
async function monthPnl(ctx, month = monthOf(ctx.date)) {
  if (!ctx.canFinance) return null;
  const b = monthBounds(month, ctx.tz);
  const current = month === monthOf(ctx.date);
  const to = current ? ctx.dayEnd : b.next;
  const r = await rangePnl(ctx, b.start, to);
  const fixed = current ? await pendingFixed(ctx, month) : { kurus: 0, count: 0 };
  return {
    month, current, day_of_month: current ? Number(ctx.date.slice(8, 10)) : b.days, days_in_month: b.days,
    ...r, fixed_pending_kurus: fixed.kurus, fixed_pending_count: fixed.count, projected_expense_kurus: r.expense_kurus + fixed.kurus,
  };
}

/** Tek gün para hareketi (İstanbul günü) */
async function dayMoney(ctx, dateStr = ctx.date) {
  if (!ctx.canFinance) return null;
  const from = clock.zonedToUtc(dateStr, "00:00", ctx.tz), to = clock.zonedToUtc(clock.addDays(dateStr, 1), "00:00", ctx.tz);
  const r = await rangePnl(ctx, from, to);
  return { date: dateStr, collected_kurus: r.collected_kurus, expense_kurus: r.expense_kurus, home_expense_kurus: r.home_expense_kurus, payments_count: r.payments_count, expenses_count: r.expenses_count };
}

module.exports = { rangePnl, monthPnl, dayMoney, pendingFixed, monthlyFixedTotal, monthBounds, prevMonth, monthOf };
