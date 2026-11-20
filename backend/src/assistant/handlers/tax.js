/**
 * Zamanlı hatırlatma işleyicileri (A1 kuyruğu: queue.registerHandler, işleyici imzası fn(payload, job)):
 *   'tax.plan'          vergi takvimi / alacak hatırlatma işlerini planlar (tax/reminderPlanner.js) ve kendini ertesi güne zincirler
 *   'tax.remind'        {userId, key, dueDate, offset}  bir vergi takvimi oluşumu için hatırlatma (son günden T−7, T−3, T−1, son gün)
 *   'receivable.remind' {userId, date?} | {userId, scheduleId|invoiceId}  tahsilat vadeleri (vadeden önce/sonra eşik günlerinde)
 * İşleyiciler İDEMPOTENTTİR: bildirim dedupeKey'i KULLANICIYI içerir (`tax:{userId}:{key}:{due}:T{off}`, `recv:{userId}:{kaynak}:{id}:D{gün}`),
 * iş iki kez çalışsa da tek bildirim çıkar. Süresi geçmiş iş kuyrukta 'skipped' olur (eski saatte bildirim atılmaz).
 * Bildirim türleri: 'tax_reminder', 'receivable_reminder' (kullanıcı tercihleriyle türe göre kapatılabilir). Metinler TAHMİNİDİR: mali müşavire teyit
 * uyarısı taşır; müşteriye bu işleyiciler HİÇBİR ŞEY GÖNDERMEZ (WhatsApp mesajı kullanıcı onayıyla wa.me ile gider).
 * Test: createHandlers({ notify: sahteNotify }) ile bağımlılık enjekte edilebilir; sahte saat için assistant/clock.setFake.
 */
const db = require("../../db");
const clock = require("../clock");
const notifySvc = require("../notify");
const planner = require("../tax/reminderPlanner");
const TC = require("../tax/taxCalendar");
const VP = require("../tax/vatPeriod");
const T = require("../tax/turkish");
const { daysBetween, addMonths, fmt } = require("../tax/dates");

const TAX_PLAN = "tax.plan";
const TAX_REMIND = "tax.remind";
const RECEIVABLE_REMIND = "receivable.remind";
const DEFAULT_TAX_OFFSETS = planner.OFFSETS;
const RECEIVABLE_DAYS = [-1, 0, 3, 7, 14, 30, 60, 90]; // vadeye göre gün (negatif = vadeden önce)
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (v) => typeof v === "string" && UUID_RE.test(v);
const isDay = (v) => typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);

function createHandlers({ notify = (...a) => notifySvc.notifyUser(...a) } = {}) {
  const vatService = () => require("../tax/vatService");
  const receivablesService = () => require("../tax/receivablesService");

  async function whoIs(userId) {
    const { rows } = await db.query("SELECT id, role, org_id FROM users WHERE id = $1", [userId]);
    if (!rows[0]) return { skip: "user_not_found" };
    if (!planner.ELIGIBLE_ROLES.includes(rows[0].role)) return { skip: "role_not_allowed" };
    const { financeOwnerId } = require("../../middleware/access");
    return { user: rows[0], ledger: await financeOwnerId(rows[0]) };
  }

  /** KDV kalemi için ilgili vergilendirme dönemi ve tahmini ödenecek tutar */
  async function vatEstimate(ledger, item, occ) {
    if (!item || !item.rule || !["kdv1_aylik", "kdv1_uc_aylik"].includes(item.key)) return null;
    const off = item.rule.period_offset_months ?? 0;
    const per = addMonths(+occ.nominal_date.slice(0, 4), +occ.nominal_date.slice(5, 7), -off);
    const key = VP.periodOfDate(item.key === "kdv1_aylik" ? "aylik" : "uc_aylik", fmt(per.y, per.m, 1));
    const [p] = await vatService().computeRange(ledger, key, key);
    return { key, odenecekKurus: p.odenecekKurus };
  }

  /** (userId, key, dueDate) → güncel oluşum (kalem silindi/kapandı/tarihi değişti ise null → iş "bayat") */
  async function findOccurrence(user, key, dueDate, today) {
    const cal = await planner.loadOrgCalendar(user.org_id, today);
    const occ = planner.occurrencesFor(cal, { from: dueDate, to: dueDate, today }).find((o) => o.key === key && o.due_date === dueDate);
    return { occ: occ || null, item: cal.items.find((i) => i.key === key) || null };
  }

  async function taxRemind(payload, job) {
    const p = payload || {};
    const userId = p.userId || (job && job.userId);
    if (!isUuid(userId)) return { skipped: "invalid_user" };
    if (!p.key || !isDay(p.dueDate)) return { skipped: "invalid_payload" };
    const who = await whoIs(userId);
    if (who.skip) return { skipped: who.skip };
    const today = clock.istanbulDateStr();
    const { occ, item } = await findOccurrence(who.user, p.key, p.dueDate, today);
    if (!occ) return { skipped: "stale" };                       // takvim kaydı değişti/kapandı: eski tarih için bildirim yok
    if (occ.days_until < 0) return { skipped: "past" };
    let estimate = null;
    try { estimate = await vatEstimate(who.ledger, item, occ); } catch { estimate = null; }
    const when = occ.days_until === 0 ? "Bugün son gün" : occ.days_until === 1 ? "Yarın son gün" : `${occ.days_until} gün kaldı`;
    const parts = [
      `${occ.period_label ? occ.period_label + " • " : ""}Son gün: ${T.formatDateTr(occ.due_date)} ${T.weekdayTr(occ.due_date)}${occ.shifted ? " (hafta sonu/resmî tatil nedeniyle ertelenmiş)" : ""}.`,
      ...(estimate && estimate.odenecekKurus > 0 ? [`Tahmini ödenecek KDV: ${T.formatTL(estimate.odenecekKurus)} TL.`] : []),
      ...(occ.needs_confirmation ? ["Tarih/tutar tahminidir; mali müşavirinize teyit edin."] : []),
    ];
    const off = Number.isInteger(p.offset) ? p.offset : occ.days_until;
    const r = await notify(userId, {
      type: "tax_reminder", title: `${when}: ${occ.title}`, body: parts.join(" "),
      data: { itemKey: occ.key, dueDate: occ.due_date, daysUntil: occ.days_until, period: estimate ? estimate.key : null, estimatedPayableKurus: estimate ? estimate.odenecekKurus : null, needsConfirmation: occ.needs_confirmation, route: "/vergi-takvimi" },
      dedupeKey: `tax:${userId}:${occ.key}:${occ.due_date}:T${off}`,
    });
    return { sent: 1, deduped: !!(r && r.deduped), key: occ.key, dueDate: occ.due_date, offset: off };
  }

  const toneFor = (daysOverdue) => (daysOverdue <= 3 ? "odeme_nazik" : daysOverdue <= 14 ? "odeme_orta" : "odeme_kesin");

  async function receivableRemind(payload, job) {
    const p = payload || {};
    const userId = p.userId || (job && job.userId);
    if (!isUuid(userId)) return { skipped: "invalid_user" };
    const who = await whoIs(userId);
    if (who.skip) return { skipped: who.skip };
    const today = clock.istanbulDateStr();
    let items = await receivablesService().loadOpenItems(who.ledger);
    const single = isUuid(p.scheduleId) ? p.scheduleId : isUuid(p.invoiceId) ? p.invoiceId : null;
    if (single) {
      items = items.filter((i) => i.id === single || i.invoice_id === single);
      if (!items.length) return { skipped: "not_pending" };         // ödendi/iptal/başka defter → hatırlatma yok
    }
    const sent = [];
    for (const it of items) {
      const daysOverdue = daysBetween(it.due_date, today);
      if (!single && !RECEIVABLE_DAYS.includes(daysOverdue)) continue;
      const who2 = it.customer_name || "Müşteri";
      const amount = `${T.formatTL(it.amount_kurus)} TL`;
      const title = daysOverdue > 0 ? `Vadesi geçti: ${who2}` : daysOverdue === 0 ? `Bugün vade: ${who2}` : `Yarın vade: ${who2}`;
      const body = daysOverdue > 0
        ? `${amount} tahsilatın vadesi ${T.formatDateTr(it.due_date)} idi (${daysOverdue} gün gecikti). Nazik bir hatırlatma mesajı hazırlayabilirsiniz.`
        : `${amount} tahsilatın vadesi ${daysOverdue === 0 ? "bugün" : "yarın"} (${T.formatDateTr(it.due_date)}).`;
      await notify(userId, {
        type: "receivable_reminder", title, body,
        data: { source: it.source, id: it.id, scheduleId: it.source === "plan" ? it.id : null, invoiceId: it.invoice_id || null, amountKurus: it.amount_kurus, dueDate: it.due_date, daysOverdue: Math.max(daysOverdue, 0), suggestedTemplateKey: daysOverdue > 0 ? toneFor(daysOverdue) : "odeme_nazik", route: "/tahsilat" },
        dedupeKey: `recv:${userId}:${it.source}:${it.id}:D${single ? today : daysOverdue}`,
      });
      sent.push({ id: it.id, daysOverdue });
    }
    return { sent: sent.length, reminders: sent, today };
  }

  async function taxPlan() {
    const r = await planner.planAll();
    await planner.scheduleNextPlan();
    return r;
  }

  return { taxRemind, receivableRemind, taxPlan };
}

/** queue.js yükleyicisi çağırır: handlers/*.js → module.exports.register(registerHandler) */
function register(registerHandler) {
  const h = createHandlers({});
  registerHandler(TAX_PLAN, h.taxPlan);
  registerHandler(TAX_REMIND, h.taxRemind);
  registerHandler(RECEIVABLE_REMIND, h.receivableRemind);
}

module.exports = { register, createHandlers, TAX_PLAN, TAX_REMIND, RECEIVABLE_REMIND, DEFAULT_TAX_OFFSETS, RECEIVABLE_DAYS };
