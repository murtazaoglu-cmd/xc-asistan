/** Alacak/fatura kuralları: M2 tahsilat gecikmesi · M2b tahsilat oranı · M7 faturasız tahsilat (invoices'a bağlı) · M8 KDV (vat_periods'a bağlı). */
const db = require("../../../db");
const clock = require("../../clock");
const tr = require("../../text/tr");
const { params: P, ownerClause } = require("../../facts/context");
const { cand, m, A } = require("./_util");

// ---------------- M2 Tahsilat gecikmesi ----------------
const M2 = {
  key: "M2", group: "tahsilat", title: "Tahsilat gecikmesi",
  description: "Teslim/Tamamlandı aşamasında, kalan bakiyesi olan ve aşamaya geçeli belirli günden uzun olan işler.",
  defaultParams: { warn_age_days: 7, critical_age_days: 21, critical_amount_floor_kurus: 2500000, critical_avg_pct_bp: 3000 },
  async collect(ctx, params, f) { return f.receivables.receivableAging(ctx); },
  evaluate(rec, p) {
    if (!rec) return [];
    const crit = Math.max(p.critical_amount_floor_kurus, Math.round((rec.avg_job_kurus * p.critical_avg_pct_bp) / 10000));
    const out = [];
    for (const it of rec.items) {
      if (!it.delivered || it.balance_kurus <= 0 || !(it.stage_age_days > p.warn_age_days)) continue;
      const critical = it.stage_age_days > p.critical_age_days || it.balance_kurus >= crit;
      out.push(cand("M2", critical ? "critical" : "warn", `M2:project:${it.project_id}`, {
        entity: { type: "project", id: it.project_id }, score: it.balance_kurus,
        vars: { name: it.customer_name, code: it.code, stage: it.stage, age: it.stage_age_days, balance: it.balance_kurus, contract: it.contract_kurus + it.extras_kurus, paid: it.paid_kurus, service: it.service, crit_threshold: crit },
        metrics: [m("balance", "Kalan bakiye", it.balance_kurus, "kurus"), m("contract", "Sözleşme + ilave", it.contract_kurus + it.extras_kurus, "kurus"), m("paid", "Tahsil edilen", it.paid_kurus, "kurus"),
          m("age", "Aşamaya geçeli gün", it.stage_age_days, "days"), m("crit_threshold", "Kritik tutar eşiği", crit, "kurus")],
        refs: [{ type: "project", id: it.project_id, label: `${it.code} · ${it.customer_name}` }],
        actions: [A.whatsapp({ template: "odeme_hatirlatma", phone: it.phone, name: it.customer_name, project_id: it.project_id, vars: { amount_kurus: it.balance_kurus, service: it.service } }),
          A.call({ phone: it.phone, name: it.customer_name, project_id: it.project_id }), A.reminder({ title: `Tahsilat: ${it.customer_name}`, project_id: it.project_id, name: it.customer_name, phone: it.phone }), A.open("project", it.project_id)],
      }));
    }
    return out;
  },
};

// ---------------- M2b Tahsilat oranı ----------------
const M2b = {
  key: "M2b", group: "tahsilat", title: "Tahsilat oranı (90 gün)",
  description: "Son 90 günde başlayan işlerde tahsil edilen / sözleşme (+ilave) oranı düşükse uyarır.",
  defaultParams: { warn_bp: 7000, critical_bp: 5000, window_days: 90, min_projects: 3 },
  async collect(ctx, params) {
    if (!ctx.canFinance) return null;
    const from = clock.zonedToUtc(clock.addDays(ctx.date, -params.window_days), "00:00", ctx.tz);
    const p = P([ctx.orgId, ctx.ledgerOwnerId, ctx.dayEnd, from]);
    const own = ownerClause(ctx, "p", "project", p, "biz");
    const { rows } = await db.query(
      `SELECT COUNT(*)::int AS n,
              COALESCE(SUM(ROUND(p.total_amount*100) + COALESCE(ex.s,0)),0)::bigint AS contract,
              COALESCE(SUM(COALESCE(pay.s,0)),0)::bigint AS paid
         FROM projects p
         LEFT JOIN (SELECT project_id, SUM(ROUND(amount*100))::bigint AS s FROM payments WHERE owner_id = $2 AND paid_at < $3 GROUP BY project_id) pay ON pay.project_id = p.id
         LEFT JOIN (SELECT project_id, SUM(ROUND(amount*100))::bigint AS s FROM project_extras WHERE created_at < $3 GROUP BY project_id) ex ON ex.project_id = p.id
        WHERE p.org_id = $1 AND p.start_date >= $4 AND p.start_date < $3 AND p.total_amount > 0${own}`, p.arr);
    return { n: rows[0].n, contract: Number(rows[0].contract), paid: Number(rows[0].paid), window_days: params.window_days };
  },
  evaluate(i, p) {
    if (!i || i.n < p.min_projects || i.contract <= 0) return [];
    const rate = Math.round((i.paid * 10000) / i.contract);
    const sev = rate < p.critical_bp ? "critical" : rate < p.warn_bp ? "warn" : null;
    if (!sev) return [];
    return [cand("M2b", sev, "M2b:ratio", {
      vars: { ...i, rate_bp: rate }, score: i.contract - i.paid,
      metrics: [m("contract", "Sözleşme (+ilave) toplamı", i.contract, "kurus"), m("paid", "Tahsil edilen", i.paid, "kurus"), m("rate", "Tahsilat oranı", rate, "bp"), m("n", "İş sayısı", i.n, "count")],
      actions: [A.screen("receivables", {})],
    })];
  },
};

// ---------------- M7 Faturasız tahsilat (BAĞIMLILIK: invoices) ----------------
const M7 = {
  key: "M7", group: "vergi", title: "Faturasız tahsilat",
  description: "Tahsil edilmiş ama karşılığında fatura kaydı olmayan tutarlar (fatura takibi tablosuna bağlıdır).",
  requires: [{ table: "invoices", cols: ["org_id", "owner_id", "project_id", "direction", "status", "odenecek_kurus"] }], // B paketi: invoices (schema_v18)
  defaultParams: { warn_days: 7, critical_days: 30, month_end_days: 5 },
  async collect(ctx) {
    if (!ctx.canFinance) return null;
    const p = P([ctx.orgId, ctx.ledgerOwnerId, ctx.dayEnd]);
    const own = ownerClause(ctx, "p", "project", p, "biz");
    const pays = await db.query(
      `SELECT pay.project_id, p.code, p.customer_name, o.phone, ROUND(pay.amount*100)::bigint AS k, to_char(pay.paid_at AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD') AS d
         FROM payments pay JOIN projects p ON p.id = pay.project_id LEFT JOIN offers o ON o.id = p.offer_id
        WHERE pay.owner_id = $2 AND p.org_id = $1 AND pay.paid_at < $3${own} ORDER BY pay.project_id, pay.paid_at ASC, pay.id`, p.arr);
    const inv = await db.query(
      // giden (satış) faturalar; iptal/taslak sayılmaz; tutar = müşterinin ödeyeceği (tevkifat düşülmüş) — tahsilatla aynı bazda karşılaştırılır
      `SELECT project_id, SUM(odenecek_kurus)::bigint AS k FROM invoices WHERE org_id = $1 AND owner_id = $2 AND direction = 'giden' AND status IN ('kesildi','gonderildi','odendi') AND project_id IS NOT NULL GROUP BY project_id`, [ctx.orgId, ctx.ledgerOwnerId]);
    const invBy = new Map(inv.rows.map((r) => [r.project_id, Number(r.k)]));
    const by = new Map();
    for (const r of pays.rows) { const x = by.get(r.project_id) || { project_id: r.project_id, code: r.code, name: r.customer_name, phone: r.phone, pays: [] }; x.pays.push({ k: Number(r.k), d: r.d }); by.set(r.project_id, x); }
    const [y, mo] = ctx.date.split("-").map(Number);
    const daysInMonth = new Date(Date.UTC(y, mo, 0)).getUTCDate();
    const items = [];
    for (const x of by.values()) {
      let cover = invBy.get(x.project_id) || 0, unbilled = 0, since = null;
      for (const pay of x.pays) {
        const covered = Math.min(cover, pay.k); cover -= covered;
        const rest = pay.k - covered;
        if (rest > 0) { unbilled += rest; if (!since) since = pay.d; }
      }
      if (unbilled > 0) items.push({ project_id: x.project_id, code: x.code, name: x.name, phone: x.phone, unbilled, since, age_days: tr.daysBetween(since, ctx.date), invoiced: invBy.get(x.project_id) || 0, paid: x.pays.reduce((s, q) => s + q.k, 0) });
    }
    return { items, days_to_month_end: daysInMonth - Number(ctx.date.slice(8, 10)) };
  },
  evaluate(i, p) {
    if (!i) return [];
    const out = [];
    for (const it of i.items) {
      if (!(it.age_days > p.warn_days)) continue;
      const critical = it.age_days > p.critical_days || i.days_to_month_end < p.month_end_days;
      out.push(cand("M7", critical ? "critical" : "warn", `M7:project:${it.project_id}`, {
        entity: { type: "project", id: it.project_id }, score: it.unbilled,
        vars: { name: it.name, code: it.code, ...it, days_to_month_end: i.days_to_month_end },
        metrics: [m("paid", "Tahsil edilen", it.paid, "kurus"), m("invoiced", "Kesilen fatura toplamı", it.invoiced, "kurus"), m("unbilled", "Faturasız tutar", it.unbilled, "kurus"), m("age", "Gün", it.age_days, "days"), m("month_end", "Ay sonuna kalan gün", i.days_to_month_end, "days")],
        refs: [{ type: "project", id: it.project_id, label: `${it.code} · ${it.name}` }], actions: [A.screen("invoices.new", { project_id: it.project_id }), A.open("project", it.project_id)],
      }));
    }
    return out;
  },
};

// ---------------- M8 KDV (BAĞIMLILIK: vat_periods) — yalnız işletme kapsamı ----------------
const M8 = {
  key: "M8", group: "vergi", title: "KDV son günü",
  description: "KDV beyan/ödeme son gününe 7 gün kala (ve gecikmede) tahmini ödenecek tutarı hatırlatır. Tutarlar tahminidir.",
  requires: [{ table: "vat_periods", cols: ["org_id", "owner_id", "period_key", "odenecek_kurus", "due_date", "status"] }], // B paketi: vat_periods (schema_v18)
  scopes: ["business"],
  defaultParams: { warn_days: 7, critical_days: 1 },
  async collect(ctx, params, f) {
    if (ctx.scopeKey !== "business") return null;
    const { rows } = await db.query(
      // kilitli (beyan edilmiş) dönemler hariç; defter sahibi = işletme defteri
      `SELECT period_key AS period, odenecek_kurus::bigint AS payable, to_char(due_date,'YYYY-MM-DD') AS due FROM vat_periods WHERE org_id = $1 AND owner_id = $2 AND status = 'acik' AND due_date IS NOT NULL ORDER BY due_date ASC LIMIT 6`, [ctx.orgId, ctx.ledgerOwnerId]);
    const pnl = await f.pnl.monthPnl(ctx);
    return { periods: rows.map((r) => ({ period: r.period, payable: Number(r.payable), due: r.due })), cash_estimate: pnl.collected_kurus - pnl.projected_expense_kurus, date: ctx.date };
  },
  evaluate(i, p) {
    if (!i) return [];
    const out = [];
    for (const v of i.periods) {
      if (v.payable <= 0) continue;
      const left = tr.daysBetween(i.date, v.due);
      if (left > p.warn_days) continue;
      const critical = left < 0 || (left <= p.critical_days && v.payable > i.cash_estimate);
      out.push(cand("M8", critical ? "critical" : "warn", `M8:${v.period}`, {
        vars: { period: v.period, payable: v.payable, due: v.due, left, cash: i.cash_estimate }, score: v.payable,
        metrics: [m("payable", "Tahmini ödenecek KDV", v.payable, "kurus"), m("due", "Son gün", v.due, "date"), m("left", "Kalan gün", left, "days"), m("cash", "Ay sonu nakit tahmini", i.cash_estimate, "kurus")],
        actions: [A.screen("vat", { period: v.period })],
      }));
    }
    return out;
  },
};

module.exports = [M2, M2b, M7, M8];
