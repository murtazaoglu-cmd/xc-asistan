/**
 * Sabah brifingi (Sekreter): bugünün randevuları, hatırlatma/takipler, dikkat (≤3), yeni talepler, geciken işler, tahsilat, düşük stok, para özeti, tek soru.
 * Kural tabanlı; sayılar facts'ten; metin şablonlu. Boş günde anlamlı metin; Pazar/resmî tatilde kısa form.
 * Rol: saha yalnız kendi atanmış işleri (finans/stok/yeni talep/insight YOK); personel finans/insight görmez; ortak yalnız kendi verisi.
 * Çıktı: {title, bodyText, data, notification:{title, body}}  — data.v = 1 (sürümlü şema)
 */
const db = require("../../db");
const clock = require("../clock");
const tr = require("../text/tr");
const facts = require("../facts");
const { loadTerms } = require("../text/terms");
const engine = require("../manager/engine");
const { apptItem, dayKind, dateHeader, contactActions } = require("./common");

const MAX_ATTENTION = 3;

/** Dünün kapanışı yapılmadı mı? → {date, unresolved, status} | null */
async function missedClosure(ctx) {
  const y = clock.addDays(ctx.date, -1);
  const [log, appts] = await Promise.all([
    db.query(`SELECT status FROM daily_logs WHERE user_id = $1 AND log_date = $2::date`, [ctx.userId, y]),
    facts.agenda.appointmentsOn(ctx, y),
  ]);
  const open = appts.filter((a) => a.state === "acik");
  const st = log.rows[0] ? log.rows[0].status : null;
  if (st === "done" || st === "skipped") return null;
  if (open.length === 0) return null;
  return { date: y, unresolved: open.length, status: st || "yok" };
}

/** Veri eksiği sorusu: aktif işte planlanan teslim (bitiş) tarihi boş */
async function dataQuestion(ctx, T) {
  if (ctx.isField) return null;
  const p = facts.context.params([ctx.orgId]);
  const own = facts.context.ownerClause(ctx, "p", "project", p, "ops");
  const { rows } = await db.query(
    `SELECT p.id, p.code, p.customer_name FROM projects p WHERE p.org_id = $1 AND p.end_date IS NULL AND p.stage IN ('Üretim','Montaj','Teslim')${own} ORDER BY p.start_date ASC LIMIT 1`, p.arr);
  if (!rows[0]) return null;
  const sat = (() => { let d = ctx.date; for (let i = 0; i < 7 && clock.zonedWeekday(clock.zonedToUtc(d, "12:00", ctx.tz), ctx.tz) !== 6; i++) d = clock.addDays(d, 1); return d; })();
  return {
    kind: "set_end_date", project_id: rows[0].id,
    text: `${rows[0].customer_name} ${T.lc("job")}: teslim tarihi boş. Girelim mi?`,
    chips: [{ label: "Bugün", value: ctx.date }, { label: "Bu hafta", value: sat }, { label: "Sonra", value: null }],
    apply: { method: "PATCH", path: `/api/projects/${rows[0].id}/dates`, body_field: "end_date" },
  };
}

function lateCollections(rec) {
  if (!rec) return { count: 0, total_kurus: 0, items: [] };
  const late = rec.items.filter((x) => x.delivered && (x.bucket === "late" || x.bucket === "severe"));
  return { count: late.length, total_kurus: late.reduce((s, x) => s + x.balance_kurus, 0), items: late.slice(0, 3) };
}

async function build(user, { date, orgId, now = clock.now() }) {
  const ctx = await facts.context.userCtx(user, { date, orgId });
  const T = await loadTerms(ctx.orgId);
  const first = tr.firstName(user.name) || "";
  const kindInfo = await dayKind(date, ctx.tz);
  const finance = ctx.canFinance;

  // Para ve insight yalnız yönetici roller; hepsi paralel
  const sk = engine.scopeKeyForUser(user);
  if (sk) await engine.ensureFresh(ctx.orgId, sk, { now }).catch((e) => console.error("[briefing] insight tazeleme hatası:", e.message));
  const [agenda, followups, rec, ydMoney, month, low, topInsights, missed, question, waiting] = await Promise.all([
    facts.agenda.dayAgenda(ctx),
    facts.followups.openFollowups(ctx),
    finance ? facts.receivables.receivableAging(ctx) : null,
    finance ? facts.pnl.dayMoney(ctx, clock.addDays(date, -1)) : null,
    finance ? facts.pnl.monthPnl(ctx) : null,
    facts.lowstock.lowStock(ctx),
    sk ? engine.top(user, ctx.orgId, MAX_ATTENTION, { now }) : [],
    missedClosure(ctx),
    kindInfo.kind ? null : dataQuestion(ctx, T),
    ctx.isField ? { items: [], count: 0 } : facts.funnel.waitingQuotes(ctx, { mode: "ops", minAgeDays: 3 }),
  ]);

  const late = lateCollections(rec);
  const apptCount = agenda.appointments.length;
  const remCount = agenda.reminders.today.length + agenda.reminders.overdue.length;
  const followCount = followups.count;
  const blocks = [];
  const rest = !!kindInfo.kind;

  if (missed) blocks.push({ id: "missed_closure", type: "missed_closure", title: "Dünün kapanışı", date: missed.date, unresolved: missed.unresolved,
    text: `Dün kapanış yapılmadı; ${T.n(missed.unresolved, "appointment")} sonucu belirsiz.`, action: { screen: "closure", date: missed.date } });

  blocks.push({ id: "appointments", type: "appointments", title: `Bugünün ${T.ek("appointments", "poss")}`, count: apptCount, items: agenda.appointments.map(apptItem),
    ...(agenda.past_open_appointments.length ? { past_open_count: agenda.past_open_appointments.length } : {}) });

  if (remCount > 0 || followCount > 0) {
    blocks.push({ id: "reminders", type: "reminders", title: "Hatırlatma ve takipler", count: remCount + followCount,
      reminders: [...agenda.reminders.overdue.map((r) => ({ ...r, overdue: true })), ...agenda.reminders.today.map((r) => ({ ...r, overdue: false }))],
      followups: followups.followups, quote_waiting: followups.quote_waiting.slice(0, 5) });
  }

  // Dikkat: yönetici roller için müdür insight'ları; diğerleri için basit türetilmiş maddeler
  let attention = [];
  if (sk) attention = topInsights.map((i) => ({ kind: "insight", insight_id: i.id, rule_key: i.rule_key, severity: i.severity, title: i.title, text: i.body, actions: i.actions.slice(0, 3) }));
  else {
    if (agenda.overdue_jobs.count > 0) attention.push({ kind: "overdue_jobs", severity: "warn", title: `${T.n(agenda.overdue_jobs.count, "job")} planlanan tarihi geçti`, text: agenda.overdue_jobs.items.map((x) => `${x.customer_name} (${x.days_overdue} gün)`).join(", ") });
    if (waiting.count > 0) attention.push({ kind: "quote_waiting", severity: "info", title: `${T.n(waiting.count, "offer")} 3 günden uzun yanıt bekliyor`, text: waiting.items.slice(0, 3).map((x) => `${x.customer_name} (${x.age_days} gün)`).join(", ") });
    attention = attention.slice(0, MAX_ATTENTION);
  }
  if (!rest || attention.some((a) => a.severity === "critical")) { if (attention.length) blocks.push({ id: "attention", type: "attention", title: "Dikkat", count: attention.length, items: rest ? attention.filter((a) => a.severity === "critical") : attention }); }

  if (!rest) {
    if (!ctx.isField && agenda.new_requests.count > 0) blocks.push({ id: "new_requests", type: "new_requests", title: `Yeni ${T.lc("offers")}`, count: agenda.new_requests.count, oldest_age_hours: agenda.new_requests.oldest_age_hours,
      items: agenda.new_requests.items.map((x) => ({ ...x, summary: `${x.customer_name}${x.service ? ` — ${x.service}` : ""}`, actions: contactActions(x.phone) })) });
    if (agenda.overdue_jobs.count > 0) blocks.push({ id: "overdue_jobs", type: "overdue_jobs", title: `Geciken ${T.lc("jobs")}`, count: agenda.overdue_jobs.count, items: agenda.overdue_jobs.items });
    if (finance && late.count > 0) blocks.push({ id: "collections", type: "collections", title: `Geciken ${T.lc("payments")}`, count: late.count, total_kurus: late.total_kurus, total_text: tr.formatTL(late.total_kurus),
      items: late.items.map((x) => ({ project_id: x.project_id, customer_name: x.customer_name, balance_kurus: x.balance_kurus, balance_text: tr.formatTL(x.balance_kurus), age_days: x.stage_age_days, actions: contactActions(x.phone) })) });
    if (low.count > 0) blocks.push({ id: "low_stock", type: "low_stock", title: "Düşük stok", count: low.count, items: low.items });
    if (finance && (ydMoney.payments_count + ydMoney.expenses_count > 0 || month.payments_count + month.expenses_count > 0)) {
      blocks.push({ id: "money", type: "money", title: "Para özeti", yesterday: { collected_kurus: ydMoney.collected_kurus, expense_kurus: ydMoney.expense_kurus },
        month: { collected_kurus: month.collected_kurus, expense_kurus: month.expense_kurus, net_kurus: month.net_kurus }, text: `Dün ${T.lc("payment")} ${tr.formatTL(ydMoney.collected_kurus)}, ${T.lc("expense")} ${tr.formatTL(ydMoney.expense_kurus)}; bu ay net ${tr.formatTL(month.net_kurus)}.` });
    }
    if (question) blocks.push({ id: "question", type: "question", title: "Tek soru", ...question });
  }

  // Başlık (bildirim): en çok 3 parça, öncelik sırasıyla
  const parts = [];
  if (apptCount) parts.push(T.n(apptCount, "appointment"));
  if (late.count) parts.push(`${late.count} geciken ${T.lc("payment")}`);
  if (followCount) parts.push(`${followCount} takip`);
  if (!ctx.isField && agenda.new_requests.count) parts.push(`${agenda.new_requests.count} yeni talep`);
  if (remCount) parts.push(`${remCount} hatırlatma`);
  const empty = apptCount === 0 && remCount === 0 && followCount === 0 && attention.length === 0 && agenda.new_requests.count === 0 && late.count === 0 && agenda.overdue_jobs.count === 0 && !missed;
  let title;
  if (kindInfo.kind && parts.length === 0) title = `Günaydın ${first}: bugün ${kindInfo.kind === "pazar" ? "Pazar" : kindInfo.name} — dinlenme günü`.replace("  ", " ");
  else if (parts.length === 0) title = `Günaydın ${first}: bugün sakin bir gün`;
  else title = `Günaydın ${first}: ${parts.slice(0, 3).join(", ")}`;
  title = title.replace("Günaydın :", "Günaydın:").replace("Günaydın  ", "Günaydın ");

  // Okunabilir metin
  const lines = [dateHeader(date) + (kindInfo.kind ? ` — ${kindInfo.kind === "tatil" ? `Resmî tatil: ${kindInfo.name}` : "Pazar"}` : "")];
  if (missed) lines.push(blocks[0].text);
  if (apptCount) lines.push(`${T.cap("appointments")}: ${agenda.appointments.map((a) => apptItem(a).summary).join("; ")}.`);
  else if (!rest) lines.push(`Bugün kayıtlı ${T.lc("appointment")} yok.`);
  if (remCount) lines.push(`Hatırlatmalar: ${[...agenda.reminders.overdue, ...agenda.reminders.today].slice(0, 5).map((r) => `${r.time} ${r.title}`).join("; ")}.`);
  if (followCount) lines.push(`Takipler: ${[...followups.followups.map((f) => f.title || "Takip"), ...followups.quote_waiting.slice(0, 3).map((q) => `${q.customer_name} (${q.age_days} gündür yanıt yok)`)].slice(0, 5).join("; ")}.`);
  if (attention.length && (!rest || attention.some((a) => a.severity === "critical"))) lines.push(`Dikkat: ${attention.filter((a) => !rest || a.severity === "critical").map((a, i) => `${i + 1}) ${a.title}`).join(" ")}`);
  if (!rest) {
    const nr = blocks.find((b) => b.id === "new_requests"); if (nr) lines.push(`Yeni ${T.lc("offers")}: ${nr.count}.`);
    const money = blocks.find((b) => b.id === "money"); if (money) lines.push(money.text);
    const q = blocks.find((b) => b.id === "question"); if (q) lines.push(q.text);
  }
  if (empty) {
    lines.push(rest
      ? "Bugün dinlenme günü; kayıtlı iş ya da hatırlatma yok. İyi dinlenmeler."
      : (waiting.count > 0
        ? `Sakin bir gün: ${T.n(waiting.count, "offer")} yanıt bekliyor; birkaçını aramak için uygun bir zaman.`
        : `Sakin bir gün: yeni ${T.lc("customers")} için aramalar yapabilir ya da kayıtları gözden geçirebilirsiniz.`));
  }
  const bodyText = lines.join("\n");

  const stats = { appointments: apptCount, reminders: remCount, followups: followCount, new_requests: ctx.isField ? 0 : agenda.new_requests.count, overdue_jobs: agenda.overdue_jobs.count, late_collections: late.count, low_stock: low.count, attention: attention.length, tomorrow_appointments: agenda.tomorrow_count };
  const data = { v: 1, kind: "morning", date, weekday: tr.weekdayName(date), date_text: tr.formatDate(date), greeting: `Günaydın ${first}`.trim(), day_kind: kindInfo.kind, holiday: kindInfo.kind === "tatil" ? kindInfo.name : null, empty, stats, blocks, role: user.role };
  let nbody;
  if (apptCount) nbody = `İlk: ${apptItem(agenda.appointments[0]).summary}`;
  else if (attention[0]) nbody = attention[0].title;
  else nbody = empty ? "Bugün için kayıtlı bir iş yok." : "Gündemi görmek için açın.";
  return { title, bodyText, data, notification: { title, body: nbody.slice(0, 300) } };
}

module.exports = { build, missedClosure, lateCollections };
