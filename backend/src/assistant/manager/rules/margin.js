/**
 * Marj kuralları: M3 düşük kâr marjı (hizmet türü) · M3b marj düşüşü.
 * YALNIZ "maliyeti onaylı" (projects.cost_confirmed_at dolu) işler hesaba girer — aksi halde yanlış "düşük marj" alarmı çıkar.
 * marj = (sözleşme + ilave − bağlı gider) / (sözleşme + ilave); gider: iş defterindeki expenses.project_id kayıtları.
 */
const db = require("../../../db");
const clock = require("../../clock");
const { params: P, ownerClause } = require("../../facts/context");
const { cand, m, A } = require("./_util");

async function confirmedJobs(ctx, from, to) {
  if (!ctx.canFinance) return [];
  const p = P([ctx.orgId, ctx.ledgerOwnerId, to, from]);
  const own = ownerClause(ctx, "p", "project", p, "biz");
  const { rows } = await db.query(
    `SELECT p.id, p.service, ROUND(p.total_amount*100)::bigint + COALESCE(ex.s,0)::bigint AS contract, COALESCE(e.s,0)::bigint AS cost
       FROM projects p
       LEFT JOIN (SELECT project_id, SUM(ROUND(amount*100))::bigint AS s FROM expenses WHERE owner_id = $2 AND expense_date < $3 GROUP BY project_id) e ON e.project_id = p.id
       LEFT JOIN (SELECT project_id, SUM(ROUND(amount*100))::bigint AS s FROM project_extras WHERE created_at < $3 GROUP BY project_id) ex ON ex.project_id = p.id
      WHERE p.org_id = $1 AND p.cost_confirmed_at IS NOT NULL AND p.total_amount > 0 AND p.start_date >= $4 AND p.start_date < $3${own}`, p.arr);
  return rows.map((r) => ({ id: r.id, service: r.service, contract: Number(r.contract), cost: Number(r.cost) }));
}
const marginBp = (contract, cost) => (contract > 0 ? Math.round(((contract - cost) * 10000) / contract) : null);

const M3 = {
  key: "M3", group: "marj", title: "Düşük kâr marjı (hizmet türü)",
  description: "Son 12 ayda maliyeti onaylı işlerde hizmet türü başına marj düşükse uyarır (tür başına en az 3 iş).",
  defaultParams: { warn_bp: 2500, critical_bp: 1500, min_jobs: 3, window_months: 12 },
  async collect(ctx, params) {
    const from = clock.zonedToUtc(clock.addDays(ctx.date, -30 * params.window_months), "00:00", ctx.tz);
    const jobs = await confirmedJobs(ctx, from, ctx.dayEnd);
    const by = new Map();
    for (const j of jobs) { const x = by.get(j.service) || { service: j.service, n: 0, contract: 0, cost: 0 }; x.n++; x.contract += j.contract; x.cost += j.cost; by.set(j.service, x); }
    return { services: [...by.values()], window_months: params.window_months };
  },
  evaluate(i, p) {
    if (!i) return [];
    const out = [];
    for (const s of i.services) {
      if (s.n < p.min_jobs) continue;
      const mb = marginBp(s.contract, s.cost);
      if (mb == null) continue;
      const sev = mb < p.critical_bp ? "critical" : mb < p.warn_bp ? "warn" : null;
      if (!sev) continue;
      out.push(cand("M3", sev, `M3:service:${s.service.toLocaleLowerCase("tr-TR")}`, {
        vars: { service: s.service, n: s.n, contract: s.contract, cost: s.cost, margin_bp: mb, months: i.window_months }, score: Math.max(0, Math.round((p.warn_bp - mb) * s.contract / 10000)),
        metrics: [m("margin", "Marj", mb, "bp"), m("contract", "Gelir (sözleşme+ilave)", s.contract, "kurus"), m("cost", "Bağlı gider", s.cost, "kurus"), m("n", "Maliyeti onaylı iş", s.n, "count")],
        refs: [{ type: "service", id: null, label: s.service }], actions: [A.screen("quote_templates", { service: s.service })],
      }));
    }
    return out;
  },
};

const M3b = {
  key: "M3b", group: "marj", title: "Marj düşüşü (90/90 gün)",
  description: "Son 90 gün marjı, önceki 90 güne göre belirgin düştüyse uyarır (iki dönemde de en az 3 maliyeti onaylı iş).",
  defaultParams: { warn_drop_bp: 800, critical_drop_bp: 1500, min_jobs: 3 },
  async collect(ctx) {
    const d90 = clock.zonedToUtc(clock.addDays(ctx.date, -90), "00:00", ctx.tz), d180 = clock.zonedToUtc(clock.addDays(ctx.date, -180), "00:00", ctx.tz);
    const [recent, prev] = await Promise.all([confirmedJobs(ctx, d90, ctx.dayEnd), confirmedJobs(ctx, d180, d90)]);
    const agg = (js) => ({ n: js.length, contract: js.reduce((s, j) => s + j.contract, 0), cost: js.reduce((s, j) => s + j.cost, 0) });
    return { recent: agg(recent), prev: agg(prev) };
  },
  evaluate(i, p) {
    if (!i || i.recent.n < p.min_jobs || i.prev.n < p.min_jobs) return [];
    const r = marginBp(i.recent.contract, i.recent.cost), pr = marginBp(i.prev.contract, i.prev.cost);
    if (r == null || pr == null) return [];
    const drop = pr - r;
    const sev = drop > p.critical_drop_bp ? "critical" : drop > p.warn_drop_bp ? "warn" : null;
    if (!sev) return [];
    return [cand("M3b", sev, "M3b:overall", {
      vars: { recent_bp: r, prev_bp: pr, drop_bp: drop, recent_n: i.recent.n, prev_n: i.prev.n }, score: Math.round((drop * i.recent.contract) / 10000),
      metrics: [m("recent", "Son 90 gün marjı", r, "bp"), m("prev", "Önceki 90 gün marjı", pr, "bp"), m("drop", "Düşüş (puan)", drop, "bp"), m("recent_n", "Son dönem iş", i.recent.n, "count"), m("prev_n", "Önceki dönem iş", i.prev.n, "count")],
      actions: [A.screen("expenses", {})],
    })];
  },
};

module.exports = [M3, M3b];
