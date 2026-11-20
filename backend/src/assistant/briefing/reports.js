/**
 * Müdür raporları: haftalık (Pzt; bir önceki Pzt–Paz haftası) ve aylık (ayın 1'i; bir önceki ay).
 * Yalnız admin/muhasebe/ortak (finans). Sayılar facts'ten; yorum yok (kural tabanlı), önerilen aksiyonlar insight'lardan ("dayanak" metrikleriyle).
 */
const db = require("../../db");
const clock = require("../clock");
const tr = require("../text/tr");
const facts = require("../facts");
const { loadTerms } = require("../text/terms");
const engine = require("../manager/engine");
const { dateHeader } = require("./common");

const TL = tr.formatTL;

async function offerMovement(ctx, from, to) {
  const p = facts.context.params([ctx.orgId, from, to]);
  const own = facts.context.ownerClause(ctx, "o", "offer", p, "biz");
  const { rows } = await db.query(
    `SELECT COUNT(*) FILTER (WHERE o.created_at >= $2 AND o.created_at < $3)::int AS new_n,
            COUNT(*) FILTER (WHERE o.status = 'Kabul Edildi' AND o.status_changed_at >= $2 AND o.status_changed_at < $3)::int AS accepted,
            COUNT(*) FILTER (WHERE o.status = 'Reddedildi' AND o.status_changed_at >= $2 AND o.status_changed_at < $3)::int AS rejected,
            COUNT(*) FILTER (WHERE o.status = 'Teklif Verildi' AND o.status_changed_at >= $2 AND o.status_changed_at < $3)::int AS quoted
       FROM offers o WHERE o.org_id = $1${own}`, p.arr);
  return rows[0];
}

const recs = (items) => items.map((i) => ({ insight_id: i.id, rule_key: i.rule_key, severity: i.severity, title: i.title, text: i.body, why: (i.evidence && i.evidence.metrics) || [], actions: i.actions.slice(0, 3) }));

async function prepInsights(user, ctx, now) {
  const sk = engine.scopeKeyForUser(user);
  if (!sk) return [];
  await engine.ensureFresh(ctx.orgId, sk, { now }).catch((e) => console.error("[reports] insight tazeleme hatası:", e.message));
  return engine.top(user, ctx.orgId, 3, { now });
}

async function buildWeekly(user, { date, orgId, now = clock.now() }) {
  const ctx = await facts.context.userCtx(user, { date, orgId });
  const T = await loadTerms(ctx.orgId);
  const monday = date; // plan Pazartesi günü çalışır; rapor bir önceki haftayı kapsar
  const from = clock.addDays(monday, -7), toEx = monday, last = clock.addDays(monday, -1);
  const fromU = clock.zonedToUtc(from, "00:00", ctx.tz), toU = clock.zonedToUtc(toEx, "00:00", ctx.tz);
  const prevFromU = clock.zonedToUtc(clock.addDays(from, -7), "00:00", ctx.tz);
  const [wk, prev, rec, conv, occ, mov, top] = await Promise.all([
    facts.pnl.rangePnl(ctx, fromU, toU), facts.pnl.rangePnl(ctx, prevFromU, fromU), facts.receivables.receivableAging(ctx),
    facts.funnel.conversion(ctx, { mode: "biz" }), facts.occupancy.occupancy(ctx, { fromDate: monday, workdays: 7 }), offerMovement(ctx, fromU, toU), prepInsights(user, ctx, now),
  ]);
  const lateItems = rec.items.filter((x) => x.delivered && (x.bucket === "late" || x.bucket === "severe"));
  const label = `${tr.formatDateShort(from)} – ${tr.formatDate(last)}`;
  const data = {
    v: 1, kind: "weekly", period: { from, to: last, label },
    money: { collected_kurus: wk.collected_kurus, expense_kurus: wk.expense_kurus, net_kurus: wk.net_kurus, home_expense_kurus: wk.home_expense_kurus, prev_net_kurus: prev.net_kurus, net_change_kurus: wk.net_kurus - prev.net_kurus,
      note: wk.home_expense_kurus > 0 ? "Kişisel giderler net hesabına dahil değildir." : null },
    offers: { new: mov.new_n, quoted: mov.quoted, accepted: mov.accepted, rejected: mov.rejected, conversion_recent_bp: conv.recent.rate_bp, conversion_prev_bp: conv.prev.rate_bp },
    late_collections: { count: lateItems.length, total_kurus: lateItems.reduce((s, x) => s + x.balance_kurus, 0), items: lateItems.slice(0, 5).map((x) => ({ project_id: x.project_id, customer_name: x.customer_name, balance_kurus: x.balance_kurus, age_days: x.stage_age_days })) },
    next_7_days: { empty_days: occ.empty_days, empty_dates: occ.empty_dates, days: occ.days },
    top_actions: recs(top),
  };
  const title = `Haftalık özet: net ${TL(wk.net_kurus)}, ${T.lc("payments")} ${TL(wk.collected_kurus)}`;
  const lines = [`Hafta: ${label}`,
    `${T.cap("payments")} ${TL(wk.collected_kurus)}, ${T.lc("expenses")} ${TL(wk.expense_kurus)}; net ${TL(wk.net_kurus)} (önceki hafta ${TL(prev.net_kurus)}).`,
    `${T.cap("offers")}: ${mov.new_n} yeni, ${mov.accepted} kabul, ${mov.rejected} red${conv.recent.rate_bp != null ? `; son 90 gün kabul oranı ${tr.formatPct(conv.recent.rate_bp)}` : ""}.`,
    lateItems.length ? `Geciken ${T.lc("payments")}: ${lateItems.length} ${T.lc("job")}, toplam ${TL(data.late_collections.total_kurus)}.` : `Geciken ${T.lc("payment")} yok.`,
    `Önümüzdeki 7 iş günü: ${occ.empty_days} gün boş.`];
  if (top.length) lines.push("Bu hafta öncelikli " + top.length + " konu: " + top.map((t, i) => `${i + 1}) ${t.title}`).join(" "));
  else lines.push("Bu hafta öne çıkan bir uyarı yok.");
  return { title, bodyText: lines.join("\n"), data, notification: { title, body: top[0] ? top[0].title : `Net ${TL(wk.net_kurus)}; ${occ.empty_days} gün boş.` } };
}

async function buildMonthly(user, { date, orgId, now = clock.now() }) {
  const ctx = await facts.context.userCtx(user, { date, orgId });
  const T = await loadTerms(ctx.orgId);
  const month = facts.pnl.prevMonth(facts.pnl.monthOf(date)); // ayın 1'i: bir önceki ay
  const before = facts.pnl.prevMonth(month);
  const [cur, prev, rec, conv, top] = await Promise.all([facts.pnl.monthPnl(ctx, month), facts.pnl.monthPnl(ctx, before), facts.receivables.receivableAging(ctx), facts.funnel.conversion(ctx, { mode: "biz" }), prepInsights(user, ctx, now)]);
  const b = facts.pnl.monthBounds(month, ctx.tz);
  const p = facts.context.params([ctx.orgId, ctx.ledgerOwnerId, b.start, b.next]);
  const own = facts.context.ownerClause(ctx, "p", "project", p, "biz");
  const svc = await db.query(
    `SELECT p.service, SUM(ROUND(pay.amount*100))::bigint AS k FROM payments pay JOIN projects p ON p.id = pay.project_id
      WHERE p.org_id = $1 AND pay.owner_id = $2 AND pay.paid_at >= $3 AND pay.paid_at < $4${own} GROUP BY p.service ORDER BY k DESC LIMIT 8`, p.arr);
  const mov = await offerMovement(ctx, b.start, b.next);
  const label = `${tr.monthName(month + "-01")} ${month.slice(0, 4)}`;
  const data = {
    v: 1, kind: "monthly", period: { month, label },
    money: { collected_kurus: cur.collected_kurus, expense_kurus: cur.expense_kurus, net_kurus: cur.net_kurus, home_expense_kurus: cur.home_expense_kurus,
      prev_month: before, prev_collected_kurus: prev.collected_kurus, prev_expense_kurus: prev.expense_kurus, prev_net_kurus: prev.net_kurus, net_change_kurus: cur.net_kurus - prev.net_kurus,
      note: cur.home_expense_kurus > 0 ? "Kişisel giderler net hesabına dahil değildir." : null },
    expense_breakdown: { by_category: cur.by_category.slice(0, 5), by_scope: cur.by_scope },
    by_service: svc.rows.map((r) => ({ service: r.service, collected_kurus: Number(r.k) })),
    receivables: { total_kurus: rec.total_kurus, delivered_total_kurus: rec.delivered_total_kurus, buckets: rec.buckets },
    offers: { new: mov.new_n, accepted: mov.accepted, rejected: mov.rejected, conversion_recent_bp: conv.recent.rate_bp, conversion_prev_bp: conv.prev.rate_bp },
    top_actions: recs(top),
  };
  const title = `Aylık rapor — ${label}: net ${TL(cur.net_kurus)}`;
  const lines = [`${label} özeti`,
    `${T.cap("payments")} ${TL(cur.collected_kurus)} (önceki ay ${TL(prev.collected_kurus)}), ${T.lc("expenses")} ${TL(cur.expense_kurus)}; net ${TL(cur.net_kurus)} (önceki ay ${TL(prev.net_kurus)}).`,
    cur.by_category[0] ? `En büyük gider kalemi: ${cur.by_category[0].category} (${TL(cur.by_category[0].kurus)}).` : "Gider kaydı yok.",
    `Açık alacak ${TL(rec.total_kurus)} (teslim edilmiş ${TL(rec.delivered_total_kurus)}).`,
    `${T.cap("offers")}: ${mov.new_n} yeni, ${mov.accepted} kabul, ${mov.rejected} red.`];
  if (top.length) lines.push("Öneriler: " + top.map((t, i) => `${i + 1}) ${t.title}`).join(" "));
  else lines.push("Bu ay için öne çıkan bir öneri yok.");
  return { title, bodyText: lines.join("\n"), data, notification: { title, body: top[0] ? top[0].title : `${T.cap("payments")} ${TL(cur.collected_kurus)}, net ${TL(cur.net_kurus)}.` } };
}

module.exports = { buildWeekly, buildMonthly };
