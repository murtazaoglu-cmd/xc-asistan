/**
 * Akşam kapanış soru motoru: sorular KODLA seçilir (LLM yok), en çok 5 soru, her biri atlanabilir, yanıt chip'le alınır.
 * Sıra "veri boşluğunu kapatma değeri"ne göre. Aynı soru (money/tomorrow/cost/stage) son 14 günde 2 kez atlandıysa sorulmaz.
 */
const db = require("../../db");
const clock = require("../clock");
const tr = require("../text/tr");
const facts = require("../facts");
const { apptItem } = require("../briefing/common");

const MAX_QUESTIONS = 5, MAX_APPT_QUESTIONS = 3, SKIP_LIMIT = 2, SKIP_WINDOW_DAYS = 14;
const NEXT_STAGE = { "Malzeme Temini": "Üretim", "Üretim": "Montaj", "Montaj": "Teslim", "Teslim": "Tamamlandı" };

const opt = (value, label, extra = {}) => ({ value, label, ...extra });

function apptOptions(T, ctx) {
  const yap = opt("yapildi", "Yapıldı");
  if (!ctx.isField) yap.follow_up = [opt("teklif_verilecek", `${T.cap("offer")} verilecek`), opt("anlastik", "Anlaştık"), opt("dusunecek", "Düşünecek"), opt("sonra_ara", "Sonra ara")];
  return [yap, opt("ertelendi", "Ertelendi"), opt("iptal", "İptal")];
}

/** Son 14 günde atlanan soru anahtarları → {skip_key: adet} */
async function skipCounts(ctx) {
  const from = clock.addDays(ctx.date, -SKIP_WINDOW_DAYS);
  const { rows } = await db.query(`SELECT answers FROM daily_logs WHERE user_id = $1 AND log_date >= $2::date AND log_date < $3::date`, [ctx.userId, from, ctx.date]);
  const out = {};
  for (const r of rows) for (const [qid, a] of Object.entries(r.answers || {})) if (a && a.skipped && a.skip_key) out[a.skip_key] = (out[a.skip_key] || 0) + 1;
  return out;
}

async function generate(ctx, T) {
  const date = ctx.date;
  const [todayAppts, tomorrow, skips] = await Promise.all([
    facts.agenda.appointmentsOn(ctx, date),
    facts.agenda.appointmentsOn(ctx, clock.addDays(date, 1)),
    skipCounts(ctx),
  ]);
  const qs = [];
  const suppressed = (k) => (skips[k] || 0) >= SKIP_LIMIT;

  // Q1 randevular: sonucu işlenmemiş (planlı/beklemede) olanlar
  todayAppts.filter((a) => a.state === "acik").slice(0, MAX_APPT_QUESTIONS).forEach((a, i) => {
    const it = apptItem(a);
    qs.push({ id: `appt:${a.id}`, kind: "appointment", value: 100 - i, skip_key: null, text: `${it.summary}: nasıl geçti?`, options: apptOptions(T, ctx),
      context: { appointment_id: a.id, time: a.time, customer_name: a.customer_name, customer_phone: a.customer_phone, type: a.type, offer_id: a.offer_id, project_id: a.project_id } });
  });

  // Q3 para (yalnız finans roller): bugün hem tahsilat hem gider zaten girildiyse sorma
  if (ctx.canFinance && !suppressed("money")) {
    const mny = await facts.pnl.dayMoney(ctx, date);
    if (!(mny.payments_count > 0 && mny.expenses_count > 0)) {
      qs.push({ id: "money", kind: "money", value: 70, skip_key: "money", text: `Bugün ${T.lc("payment")} ya da ${T.lc("expense")} oldu mu?`,
        options: [opt("yok", "Yok"), opt("tahsilat", `+ ${T.cap("payment")}`), opt("gider", `+ ${T.cap("expense")}`)],
        context: { recorded_collected_kurus: mny.collected_kurus, recorded_expense_kurus: mny.expense_kurus, payments_count: mny.payments_count, expenses_count: mny.expenses_count } });
    }
  }

  // Q2 aşama: bugün randevusu olan (işi ilerlemiş olabilir) ve aşaması sürmekte olan iş
  if (!ctx.isField) {
    const pids = [...new Set(todayAppts.map((a) => a.project_id).filter(Boolean))];
    if (pids.length) {
      const p = facts.context.params([pids, ctx.orgId]);
      const { rows } = await db.query(`SELECT p.id, p.customer_name, p.stage FROM projects p WHERE p.id = ANY($1) AND p.org_id = $2 AND p.stage <> 'Tamamlandı'${facts.context.ownerClause(ctx, "p", "project", p, "ops")} LIMIT 3`, p.arr);
      for (const r of rows) {
        const next = NEXT_STAGE[r.stage];
        if (!next || suppressed(`stage:${r.id}`)) continue;
        qs.push({ id: `stage:${r.id}`, kind: "stage", value: 60, skip_key: `stage:${r.id}`, text: `${r.customer_name} ${T.lc("job")}: ${r.stage} → ${next}?`,
          options: [opt("evet", "Evet"), opt("hayir", "Hayır"), opt("sonra", "Sonra")], context: { project_id: r.id, from: r.stage, to: next } });
        break;
      }
    }
  }

  // Q4 maliyet onayı (marj hesabı için): teslim edilmiş, maliyeti onaylanmamış en yeni iş
  if (ctx.canFinance) {
    const p = facts.context.params([ctx.orgId]);
    const own = facts.context.ownerClause(ctx, "p", "project", p, "biz");
    const { rows } = await db.query(
      `SELECT p.id, p.customer_name, p.code FROM projects p WHERE p.org_id = $1 AND p.stage IN ('Teslim','Tamamlandı') AND p.cost_confirmed_at IS NULL AND p.total_amount > 0${own} ORDER BY p.stage_changed_at DESC LIMIT 5`, p.arr);
    const r = rows.find((x) => !suppressed(`cost:${x.id}`));
    if (r) qs.push({ id: `cost:${r.id}`, kind: "cost", value: 50, skip_key: `cost:${r.id}`, text: `${r.customer_name} (${r.code}) için masraflar tamam mı?`, options: [opt("tamam", "Tamam"), opt("eksik_var", "Eksik var")], context: { project_id: r.id } });
  }

  // Q5 yarın hazırlığı
  if (tomorrow.length > 0 && !suppressed("tomorrow")) {
    const noAddr = tomorrow.filter((a) => !a.address).length;
    qs.push({ id: "tomorrow", kind: "tomorrow", value: 40, skip_key: "tomorrow",
      text: `Yarın ${T.n(tomorrow.length, "appointment")}${noAddr ? `, ${noAddr} tanesinde ${T.lc("location")} eksik` : ""}. Hazır mıyız?`,
      options: [opt("tamam", "Tamam"), opt("hatirlat", "+ Hatırlat")], context: { count: tomorrow.length, missing_address: noAddr, first_time: tomorrow[0].time } });
  }

  qs.sort((a, b) => b.value - a.value);
  const picked = qs.slice(0, MAX_QUESTIONS).map(({ value, ...q }) => ({ ...q, skippable: true }));
  return { questions: picked, tomorrow_count: tomorrow.length };
}

module.exports = { generate, NEXT_STAGE, MAX_QUESTIONS, SKIP_LIMIT };
