/**
 * Tahsilat yaşlandırma (alacak). Para KURUŞ tamsayısıdır.
 *   kalan = sözleşme (total_amount) + ilave işler − tahsilat (defter: ctx.ledgerOwnerId, paid_at < gün sonu)
 * Yaş = aşamaya (Teslim/Tamamlandı) geçişten bu yana gün (projects.stage_changed_at; göç öncesi kayıtlarda göç anı).
 * Kovalar (yalnız teslim edilmiş işler): current 0–7 gün · late 8–21 · severe 22+; aşama Teslim öncesi → in_progress (henüz vadesi gelmemiş alacak).
 * Yalnız canFinance roller (admin/muhasebe/ortak); diğerleri → null (saha/personel finans görmez).
 */
const db = require("../../db");
const { params, ownerClause } = require("./context");

const DELIVERED = ["Teslim", "Tamamlandı"];

async function receivableAging(ctx) {
  if (!ctx.canFinance) return null;
  const p = params([ctx.orgId, ctx.ledgerOwnerId, ctx.dayEnd, ctx.date]);
  const own = ownerClause(ctx, "p", "project", p, "biz");
  const { rows } = await db.query(
    `SELECT p.id, p.code, p.customer_name, p.service, p.stage, p.owner_id, o.phone, o.id AS offer_id,
            ROUND(p.total_amount*100)::bigint AS total_k, COALESCE(ex.s,0)::bigint AS extras_k, COALESCE(pay.s,0)::bigint AS paid_k,
            ($4::date - (p.stage_changed_at AT TIME ZONE 'Europe/Istanbul')::date) AS stage_age_days
       FROM projects p
       LEFT JOIN offers o ON o.id = p.offer_id
       LEFT JOIN (SELECT project_id, SUM(ROUND(amount*100))::bigint AS s FROM payments WHERE owner_id = $2 AND paid_at < $3 GROUP BY project_id) pay ON pay.project_id = p.id
       LEFT JOIN (SELECT project_id, SUM(ROUND(amount*100))::bigint AS s FROM project_extras WHERE created_at < $3 GROUP BY project_id) ex ON ex.project_id = p.id
      WHERE p.org_id = $1${own}`, p.arr);
  const items = [];
  let totalContract = 0, nContract = 0;
  for (const r of rows) {
    const total = Number(r.total_k), extras = Number(r.extras_k), paid = Number(r.paid_k);
    if (total > 0) { totalContract += total; nContract++; }
    const balance = total + extras - paid;
    if (balance <= 0) continue;
    const delivered = DELIVERED.includes(r.stage);
    const age = Math.max(0, r.stage_age_days == null ? 0 : r.stage_age_days);
    items.push({ project_id: r.id, code: r.code, customer_name: r.customer_name, service: r.service, stage: r.stage, phone: r.phone || null, offer_id: r.offer_id || null,
      contract_kurus: total, extras_kurus: extras, paid_kurus: paid, balance_kurus: balance, delivered, stage_age_days: age,
      bucket: !delivered ? "in_progress" : age <= 7 ? "current" : age <= 21 ? "late" : "severe" });
  }
  items.sort((a, b) => b.balance_kurus - a.balance_kurus);
  const buckets = { current: { count: 0, kurus: 0 }, late: { count: 0, kurus: 0 }, severe: { count: 0, kurus: 0 }, in_progress: { count: 0, kurus: 0 } };
  for (const it of items) { buckets[it.bucket].count++; buckets[it.bucket].kurus += it.balance_kurus; }
  const sum = (f) => items.filter(f).reduce((s, x) => s + x.balance_kurus, 0);
  return {
    as_of: ctx.date, count: items.length, total_kurus: sum(() => true), delivered_total_kurus: sum((x) => x.delivered), in_progress_total_kurus: sum((x) => !x.delivered),
    avg_job_kurus: nContract ? Math.round(totalContract / nContract) : 0, buckets, items,
  };
}

module.exports = { receivableAging, DELIVERED };
