/** Para kuralları: M1 nakit açığı · M9 gider sıçraması · M10 müşteri bağımlılığı · M13 mevsim kıyası. */
const db = require("../../../db");
const clock = require("../../clock");
const tr = require("../../text/tr");
const { cand, m, A } = require("./_util");

// ---------------- M1 Nakit açığı (ay-içi) ----------------
const M1 = {
  key: "M1", group: "para", title: "Nakit açığı (ay-içi)",
  description: "Ay-içi net = tahsilat − işletme gideri (dükkân+genel; kişisel hariç). Belirli günden sonra net düşükse ya da tahmini gider tahsilatı aşıyorsa uyarır.",
  defaultParams: { warn_after_day: 10, critical_after_day: 15, warn_net_pct_bp: 1500 },
  async collect(ctx, params, f) {
    const pnl = await f.pnl.monthPnl(ctx);
    const rec = await f.receivables.receivableAging(ctx);
    const delivered = rec ? rec.items.filter((x) => x.delivered) : [];
    return {
      month: pnl.month, day_of_month: pnl.day_of_month, collected: pnl.collected_kurus, expense: pnl.expense_kurus, home: pnl.home_expense_kurus,
      fixed_pending: pnl.fixed_pending_kurus, projected: pnl.projected_expense_kurus,
      delivered_total: delivered.reduce((s, x) => s + x.balance_kurus, 0), delivered_count: delivered.length,
      top: delivered.slice(0, 3).map((x) => ({ project_id: x.project_id, customer_name: x.customer_name, phone: x.phone, balance: x.balance_kurus, age_days: x.stage_age_days })),
    };
  },
  evaluate(i, p) {
    if (!i || (i.collected === 0 && i.expense === 0)) return []; // veri tamlığı kapısı: hareket yok
    const net = i.collected - i.expense;
    const critical = i.day_of_month >= p.critical_after_day && net < 0;
    const warn = i.day_of_month >= p.warn_after_day && (net * 10000 < p.warn_net_pct_bp * i.collected || i.projected > i.collected);
    if (!critical && !warn) return [];
    const actions = [];
    for (const t of i.top) {
      actions.push(A.whatsapp({ template: "odeme_hatirlatma", phone: t.phone, name: t.customer_name, project_id: t.project_id, vars: { amount_kurus: t.balance } }));
      actions.push(A.reminder({ title: `Ara: ${t.customer_name}`, project_id: t.project_id, name: t.customer_name, phone: t.phone }));
    }
    return [cand("M1", critical ? "critical" : "warn", `M1:${i.month}`, {
      vars: { ...i, net }, score: Math.max(0, -net),
      metrics: [m("collected", "Ay tahsilatı", i.collected, "kurus"), m("expense", "İşletme gideri", i.expense, "kurus"), m("net", "Net", net, "kurus"),
        m("fixed_pending", "Uygulanmamış sabit gider", i.fixed_pending, "kurus"), m("projected", "Tahmini ay gideri", i.projected, "kurus"), m("day", "Ayın günü", i.day_of_month, "count"),
        m("delivered_total", "Teslim edilmiş açık bakiye", i.delivered_total, "kurus")],
      refs: i.top.map((t) => ({ type: "project", id: t.project_id, label: t.customer_name })), actions,
    })];
  },
};

// ---------------- M9 Gider sıçraması ----------------
const M9 = {
  key: "M9", group: "para", title: "Gider sıçraması (kategori)",
  description: "Bu ayki kategori gideri, önceki 3 ayın aylık ortalamasına göre belirgin yüksekse uyarır (kişisel giderler hariç).",
  defaultParams: { warn_pct_bp: 4000, critical_pct_bp: 8000, min_amount_kurus: 500000, min_history_months: 2 },
  async collect(ctx, params, f) {
    const month = f.pnl.monthOf(ctx.date);
    const cur = await f.pnl.monthPnl(ctx, month);
    const prevs = [];
    let mo = month;
    for (let k = 0; k < 3; k++) { mo = f.pnl.prevMonth(mo); const b = f.pnl.monthBounds(mo, ctx.tz); prevs.push({ month: mo, r: await f.pnl.rangePnl(ctx, b.start, b.next) }); }
    const cats = new Map();
    for (const c of cur.by_category) cats.set(c.category, { category: c.category, current: c.kurus, prev_total: 0 });
    for (const pm of prevs) for (const c of pm.r.by_category) { const x = cats.get(c.category) || { category: c.category, current: 0, prev_total: 0 }; x.prev_total += c.kurus; cats.set(c.category, x); }
    return { month, categories: [...cats.values()], months_with_data: prevs.filter((x) => x.r.expense_kurus > 0).length };
  },
  evaluate(i, p) {
    if (!i || i.months_with_data < p.min_history_months) return [];
    const out = [];
    for (const c of i.categories) {
      const avg = Math.round(c.prev_total / 3);
      if (avg <= 0 || c.current <= p.min_amount_kurus) continue;
      const jump = Math.round(((c.current - avg) * 10000) / avg);
      const sev = jump > p.critical_pct_bp ? "critical" : jump > p.warn_pct_bp ? "warn" : null;
      if (!sev) continue;
      out.push(cand("M9", sev, `M9:${i.month}:${c.category.toLocaleLowerCase("tr-TR")}`, {
        vars: { category: c.category, current: c.current, avg, jump_bp: jump }, score: c.current - avg,
        metrics: [m("current", "Bu ay", c.current, "kurus"), m("avg3", "Önceki 3 ay ortalaması", avg, "kurus"), m("jump", "Artış", jump, "bp")],
        refs: [{ type: "expense_category", id: null, label: c.category }], actions: [A.screen("expenses", { category: c.category })],
      }));
    }
    return out;
  },
};

// ---------------- M10 Müşteri bağımlılığı ----------------
const M10 = {
  key: "M10", group: "para", title: "Müşteri bağımlılığı",
  description: "Son 90 günde tahsilatın büyük kısmı tek müşteriden geliyorsa bilgilendirir.",
  defaultParams: { warn_bp: 5000, critical_bp: 7000, window_days: 90, min_total_kurus: 1000000, min_payments: 3 },
  async collect(ctx, params) {
    const from = clock.zonedToUtc(clock.addDays(ctx.date, -params.window_days), "00:00", ctx.tz);
    const { rows } = await db.query(
      `SELECT COALESCE(NULLIF(regexp_replace(COALESCE(o.phone,''),'[^0-9]','','g'),''), lower(p.customer_name)) AS ckey,
              (array_agg(p.customer_name ORDER BY pay.paid_at DESC))[1] AS name,
              SUM(ROUND(pay.amount*100))::bigint AS k, COUNT(*)::int AS n
         FROM payments pay JOIN projects p ON p.id = pay.project_id LEFT JOIN offers o ON o.id = p.offer_id
        WHERE pay.owner_id = $1 AND pay.org_id = $2 AND pay.paid_at >= $3 AND pay.paid_at < $4 GROUP BY 1 ORDER BY k DESC`,
      [ctx.ledgerOwnerId, ctx.orgId, from, ctx.dayEnd]);
    const total = rows.reduce((s, r) => s + Number(r.k), 0);
    return { total, payments: rows.reduce((s, r) => s + r.n, 0), customers: rows.length, top: rows[0] ? { key: rows[0].ckey, name: rows[0].name, kurus: Number(rows[0].k) } : null, window_days: params.window_days };
  },
  evaluate(i, p) {
    if (!i || !i.top || i.total < p.min_total_kurus || i.payments < p.min_payments) return [];
    const share = Math.round((i.top.kurus * 10000) / i.total);
    const sev = share > p.critical_bp ? "critical" : share > p.warn_bp ? "warn" : null;
    if (!sev) return [];
    return [cand("M10", sev, "M10:top", {
      vars: { name: i.top.name, top: i.top.kurus, total: i.total, share_bp: share, days: i.window_days }, score: i.top.kurus,
      metrics: [m("top", "En büyük müşteri tahsilatı", i.top.kurus, "kurus"), m("total", "Toplam tahsilat", i.total, "kurus"), m("share", "Pay", share, "bp"), m("customers", "Müşteri sayısı", i.customers, "count")],
      refs: [{ type: "customer", id: null, label: i.top.name }], actions: [A.screen("customers", {})],
    })];
  },
};

// ---------------- M13 Mevsim kıyası ----------------
const M13 = {
  key: "M13", group: "para", title: "Mevsim kıyası (geçen yıl)",
  description: "Ayın ilk günlerinde tahsilat, geçen yıl aynı dönemden belirgin düşükse bilgilendirir (≥12 ay veri gerekir).",
  defaultParams: { warn_drop_bp: 2500, critical_drop_bp: 4000, min_day_of_month: 10, min_last_year_kurus: 500000 },
  async collect(ctx) {
    const [y, mo, d] = ctx.date.split("-").map(Number);
    const first = await db.query("SELECT MIN(paid_at) AS t FROM payments WHERE owner_id = $1 AND org_id = $2", [ctx.ledgerOwnerId, ctx.orgId]);
    const daysLY = new Date(Date.UTC(y - 1, mo, 0)).getUTCDate();
    const dd = Math.min(d, daysLY);
    const mm = String(mo).padStart(2, "0");
    const sum = async (from, to) => Number((await db.query("SELECT COALESCE(SUM(ROUND(amount*100)),0)::bigint AS k FROM payments WHERE owner_id = $1 AND org_id = $2 AND paid_at >= $3 AND paid_at < $4", [ctx.ledgerOwnerId, ctx.orgId, from, to])).rows[0].k);
    const cur = await sum(clock.zonedToUtc(`${y}-${mm}-01`, "00:00", ctx.tz), ctx.dayEnd);
    const ly = await sum(clock.zonedToUtc(`${y - 1}-${mm}-01`, "00:00", ctx.tz), clock.zonedToUtc(clock.addDays(`${y - 1}-${mm}-${String(dd).padStart(2, "0")}`, 1), "00:00", ctx.tz));
    const earliest = first.rows[0].t ? clock.zonedDateStr(first.rows[0].t, ctx.tz) : null;
    return { month: `${y}-${mm}`, day: d, current: cur, last_year: ly, history_days: earliest ? tr.daysBetween(earliest, ctx.date) : 0 };
  },
  evaluate(i, p) {
    if (!i || i.history_days < 365 || i.day < p.min_day_of_month || i.last_year < p.min_last_year_kurus) return [];
    const drop = Math.round(((i.last_year - i.current) * 10000) / i.last_year);
    const sev = drop >= p.critical_drop_bp ? "critical" : drop >= p.warn_drop_bp ? "warn" : null;
    if (!sev) return [];
    return [cand("M13", sev, `M13:${i.month}`, {
      vars: { ...i, drop_bp: drop }, score: i.last_year - i.current,
      metrics: [m("current", "Bu ay (şimdiye kadar)", i.current, "kurus"), m("last_year", "Geçen yıl aynı dönem", i.last_year, "kurus"), m("drop", "Fark", -drop, "bp"), m("day", "Ayın günü", i.day, "count")],
      actions: [A.screen("reports", { range: "monthly" })],
    })];
  },
};

module.exports = [M1, M9, M10, M13];
