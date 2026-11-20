/**
 * Akşam kapanış: günlük (daily_logs) oluştur/oku, yanıtları işle, gün sonu özeti kartı.
 *
 * Yanıtın yan etkileri:
 *   DOĞRUDAN uygulanır (asistanın kendi alanı, geri alınabilir): randevu durumu (Yapıldı → 'tamamlandı', Ertelendi → 'ertelendi', İptal → 'iptal'),
 *     takipler (followups), yarın hazırlık hatırlatması, projects.cost_confirmed_at (maliyet onayı).
 *   ÖNERİ olarak döner (closure_proposals; başka alanlara yazar, onay kartı + mevcut uçla uygulanır): tahsilat/gider kaydı, teklif durumu (Anlaştık),
 *     proje aşaması, ertelenen randevuya yeni tarih. `ai_actions` tablosu (C paketi) bu sürümde YAZILMAZ — sözleşme: closure_proposals[].apply = mevcut uca çağrı tarifi.
 * İdempotent: aynı yanıt iki kez gönderilse aynı sonuç (takipler source_key ile tekil; durum güncellemeleri sabit).
 */
const db = require("../../db");
const clock = require("../clock");
const tr = require("../text/tr");
const facts = require("../facts");
const { loadTerms } = require("../text/terms");
const reminderSvc = require("../reminders/service");
const briefStore = require("../briefing/store");
const { apptItem } = require("../briefing/common");
const questions = require("./questions");

const STALE_MS = 30 * 60 * 1000;
const FOLLOW = { teklif_verilecek: { days: 1, kind: "teklif" }, dusunecek: { days: 2, kind: "ara" }, sonra_ara: { days: 3, kind: "ara" } };

const COLS = `id, to_char(log_date,'YYYY-MM-DD') AS log_date, status, questions, answers, free_note, completeness, summary, generated_at, nudged_at, closed_at`;

async function readLog(userId, date) {
  const { rows } = await db.query(`SELECT ${COLS} FROM daily_logs WHERE user_id = $1 AND log_date = $2::date`, [userId, date]);
  return rows[0] || null;
}

/** Günlüğü getir; yoksa (ya da hiç yanıt verilmemiş ve 30 dk'dan eskiyse) soruları yeniden üretip kaydet */
async function ensureLog(user, { date, orgId, now = clock.now(), refresh = false }) {
  const ctx = await facts.context.userCtx(user, { date, orgId });
  const T = await loadTerms(ctx.orgId);
  let row = await readLog(user.id, date);
  const untouched = row && row.status === "pending" && Object.keys(row.answers || {}).length === 0 && !row.free_note;
  const stale = row && untouched && now - new Date(row.generated_at) > STALE_MS;
  if (!row || (untouched && (stale || refresh))) {
    const g = await questions.generate(ctx, T);
    await db.query(
      `INSERT INTO daily_logs (org_id, user_id, log_date, questions, generated_at) VALUES ($1,$2,$3::date,$4,$5)
       ON CONFLICT (user_id, log_date) DO UPDATE SET questions = EXCLUDED.questions, generated_at = EXCLUDED.generated_at
         WHERE daily_logs.status = 'pending' AND daily_logs.answers = '{}'::jsonb`, [ctx.orgId, user.id, date, JSON.stringify(g.questions), now]);
    row = await readLog(user.id, date);
  }
  return { row, ctx, T };
}

const tomorrowStr = (date) => clock.addDays(date, 1);

/** Gün sonu özeti kartı (güncel kayıt durumundan) */
async function summaryCard(ctx, T, row) {
  const [appts, tomorrow, money, offers] = await Promise.all([
    facts.agenda.appointmentsOn(ctx, ctx.date, { includeCancelled: true }),
    facts.agenda.appointmentsOn(ctx, tomorrowStr(ctx.date)),
    ctx.canFinance ? facts.pnl.dayMoney(ctx, ctx.date) : null,
    ctx.isField ? { count: 0 } : (async () => {
      const p = facts.context.params([ctx.orgId, ctx.dayStart, ctx.dayEnd]);
      const r = await db.query(`SELECT COUNT(*)::int AS n FROM offers o WHERE o.org_id = $1 AND o.created_at >= $2 AND o.created_at < $3${facts.context.ownerClause(ctx, "o", "offer", p, "ops")}`, p.arr);
      return { count: r.rows[0].n };
    })(),
  ]);
  const by = { tamamlandi: 0, ertelendi: 0, iptal: 0, acik: 0 };
  for (const a of appts) by[a.state] = (by[a.state] || 0) + 1;
  const qs = row.questions || [], ans = row.answers || {};
  const answered = qs.filter((q) => ans[q.id] && !ans[q.id].skipped).length;
  const skipped = qs.filter((q) => ans[q.id] && ans[q.id].skipped).length;
  const fu = await db.query(`SELECT COUNT(*)::int AS n FROM followups WHERE user_id = $1 AND source = 'kapanis' AND source_key LIKE $2 AND status = 'acik'`, [ctx.userId, `closure:${ctx.date}:%`]);
  const card = {
    title: "Gün sonu özeti", date: ctx.date, date_text: tr.formatDate(ctx.date),
    appointments: { total: appts.length, done: by.tamamlandi, postponed: by.ertelendi, cancelled: by.iptal, open: by.acik },
    money: money ? { collected_kurus: money.collected_kurus, expense_kurus: money.expense_kurus } : null,
    new_requests_today: offers.count,
    followups_created: fu.rows[0].n,
    tomorrow: { count: tomorrow.length, first: tomorrow[0] ? apptItem(tomorrow[0]).summary : null },
    completion: { total: qs.length, answered, skipped, percent: qs.length ? Math.round((answered * 100) / qs.length) : 100 },
  };
  const lines = [];
  if (appts.length) lines.push(`${T.n(appts.length, "appointment")}: ${by.tamamlandi} yapıldı${by.ertelendi ? `, ${by.ertelendi} ertelendi` : ""}${by.iptal ? `, ${by.iptal} iptal` : ""}${by.acik ? `, ${by.acik} sonuçsuz` : ""}.`);
  else lines.push(`Bugün ${T.lc("appointment")} yoktu.`);
  if (money) lines.push(`${T.cap("payment")} ${tr.formatTL(money.collected_kurus)}, ${T.lc("expense")} ${tr.formatTL(money.expense_kurus)}.`);
  if (offers.count) lines.push(`${offers.count} yeni ${T.lc("offer")} talebi geldi.`);
  lines.push(tomorrow.length ? `Yarın: ${T.n(tomorrow.length, "appointment")}${card.tomorrow.first ? ` (ilk: ${card.tomorrow.first})` : ""}.` : `Yarın için ${T.lc("appointment")} görünmüyor.`);
  card.text = lines.join(" ");
  return card;
}

function present(row, card, ctx) {
  const ans = row.answers || {};
  return {
    date: row.log_date, status: row.status, completeness: row.completeness, closed_at: row.closed_at ? new Date(row.closed_at).toISOString() : null,
    questions: (row.questions || []).map((q) => ({ ...q, answer: ans[q.id] ? { choice: ans[q.id].choice || null, follow_up: ans[q.id].follow_up || null, skipped: !!ans[q.id].skipped, answered_at: ans[q.id].answered_at } : null })),
    free_note: row.free_note, note_prompt: "Not düşmek istediğiniz bir şey var mı?", skip_label: "Atla",
    summary_card: card, closure_proposals: (row.summary && row.summary.proposals) || [],
  };
}

async function getToday(user, { date, orgId, now = clock.now(), refresh = false }) {
  const { row, ctx, T } = await ensureLog(user, { date, orgId, now, refresh });
  const card = await summaryCard(ctx, T, row);
  return present(row, card, ctx);
}

/** Gövde doğrulaması (hiçbir yan etki olmadan) → {answers:[normalized]} | {error} */
function validate(body, log) {
  const b = body && typeof body === "object" && !Array.isArray(body) ? body : null;
  if (!b) return { error: "Geçersiz gövde." };
  for (const k of Object.keys(b)) if (!["date", "answers", "free_note", "finish"].includes(k)) return { error: `Bilinmeyen alan: ${k}` };
  if (b.answers !== undefined && (!Array.isArray(b.answers) || b.answers.length > 20)) return { error: "answers en çok 20 öğeli dizi olmalı." };
  if (b.free_note !== undefined && b.free_note !== null && (typeof b.free_note !== "string" || b.free_note.length > 2000)) return { error: "free_note en çok 2000 karakterli metin olmalı." };
  if (b.finish !== undefined && typeof b.finish !== "boolean") return { error: "finish true/false olmalı." };
  const qmap = new Map((log.questions || []).map((q) => [q.id, q]));
  const out = [];
  for (const a of b.answers || []) {
    if (!a || typeof a !== "object" || typeof a.question_id !== "string") return { error: "Her yanıtta question_id gerekli." };
    for (const k of Object.keys(a)) if (!["question_id", "choice", "follow_up", "skipped", "amount_kurus", "project_id", "category", "note"].includes(k)) return { error: `Yanıtta bilinmeyen alan: ${k}` };
    const q = qmap.get(a.question_id);
    if (!q) return { error: `Bu günün kapanışında '${a.question_id}' sorusu yok.` };
    const n = { question_id: q.id };
    if (a.skipped === true) { n.skipped = true; out.push({ q, a: n }); continue; }
    if (a.skipped !== undefined && a.skipped !== false) return { error: "skipped true/false olmalı." };
    const op = q.options.find((o) => o.value === a.choice);
    if (!op) return { error: `${q.id}: geçersiz seçim. İzin verilenler: ${q.options.map((o) => o.value).join(", ")}.` };
    n.choice = a.choice;
    if (a.follow_up !== undefined && a.follow_up !== null) {
      if (a.choice !== "yapildi" || !(op.follow_up || []).some((f) => f.value === a.follow_up)) return { error: `${q.id}: geçersiz follow_up.` };
      n.follow_up = a.follow_up;
    }
    if (a.amount_kurus !== undefined) {
      if (!["money"].includes(q.kind) || !Number.isInteger(a.amount_kurus) || a.amount_kurus <= 0 || a.amount_kurus > 1e12) return { error: `${q.id}: amount_kurus 1..1e12 arası tam sayı (kuruş) olmalı ve yalnız para sorusunda geçerli.` };
      n.amount_kurus = a.amount_kurus;
    }
    if (a.project_id !== undefined) { if (typeof a.project_id !== "string" || !/^[0-9a-f-]{36}$/i.test(a.project_id)) return { error: `${q.id}: geçersiz project_id.` }; n.project_id = a.project_id; }
    for (const k of ["category", "note"]) if (a[k] !== undefined) { if (typeof a[k] !== "string" || a[k].length > 200) return { error: `${q.id}: ${k} en çok 200 karakter.` }; n[k] = a[k]; }
    out.push({ q, a: n });
  }
  return { answers: out, free_note: b.free_note === undefined ? undefined : b.free_note, finish: !!b.finish };
}

const ymdAt = (ymd, hhmm = "09:00") => clock.zonedToUtc(ymd, hhmm);

/** Tek yanıtın yan etkileri → {applied:[], proposals:[]} */
async function applyOne(ctx, T, user, date, q, a) {
  const applied = [], proposals = [];
  if (a.skipped) return { applied, proposals };
  const c = q.context || {};
  const keyBase = `closure:${date}:${q.id}`;
  const cancelStale = async (keepKey) => db.query(
    `UPDATE followups SET status = 'iptal' WHERE user_id = $1 AND source = 'kapanis' AND source_key LIKE $2 AND source_key <> $3 AND status = 'acik'`, [user.id, `${keyBase}:%`, keepKey || ""]);

  if (q.kind === "appointment") {
    const visible = (await facts.agenda.appointmentsOn(ctx, date, { includeCancelled: true })).find((x) => x.id === c.appointment_id);
    if (!visible) throw Object.assign(new Error("Bu randevuya erişiminiz yok ya da randevu bulunamadı."), { status: 403 });
    const to = { yapildi: "tamamlandı", ertelendi: "ertelendi", iptal: "iptal" }[a.choice];
    const cur = await db.query("SELECT status FROM appointments WHERE id = $1", [c.appointment_id]);
    if (cur.rows[0] && cur.rows[0].status !== to) await db.query("UPDATE appointments SET status = $2 WHERE id = $1", [c.appointment_id, to]);
    applied.push({ type: "appointment_status", id: c.appointment_id, from: cur.rows[0] ? cur.rows[0].status : null, to });
    let keepKey = null;
    if (a.choice === "yapildi" && a.follow_up && !ctx.isField) {
      if (FOLLOW[a.follow_up]) {
        const f = FOLLOW[a.follow_up];
        keepKey = `${keyBase}:${a.follow_up}`;
        const name = c.customer_name || "Müşteri";
        const title = a.follow_up === "teklif_verilecek" ? `${T.cap("offer")} hazırla: ${name}` : a.follow_up === "dusunecek" ? `Takip: ${name}` : `Ara: ${name}`;
        const ins = await db.query(
          `INSERT INTO followups (org_id, user_id, kind, title, due_date, offer_id, project_id, appointment_id, customer_name, customer_phone, source, source_key)
           VALUES ($1,$2,$3,$4,$5::date,$6,$7,$8,$9,$10,'kapanis',$11) ON CONFLICT (user_id, source_key) WHERE source_key IS NOT NULL DO NOTHING RETURNING id`,
          [ctx.orgId, user.id, f.kind, title, clock.addDays(date, f.days), c.offer_id || null, c.project_id || null, c.appointment_id, c.customer_name || null, c.customer_phone || null, keepKey]);
        const id = ins.rows[0] ? ins.rows[0].id : (await db.query("SELECT id FROM followups WHERE user_id = $1 AND source_key = $2", [user.id, keepKey])).rows[0].id;
        await db.query("UPDATE followups SET status = 'acik' WHERE id = $1 AND status = 'iptal'", [id]);
        applied.push({ type: "followup", id, kind: f.kind, due_date: clock.addDays(date, f.days), title });
      } else if (a.follow_up === "anlastik" && c.offer_id) {
        proposals.push({ type: "offer_status", question_id: q.id, offer_id: c.offer_id, to: "Kabul Edildi", label: `${T.cap("offer")} durumunu "Kabul Edildi" yap`,
          apply: { method: "PATCH", path: `/api/offers/${c.offer_id}/status`, body: { status: "Kabul Edildi" } } });
      }
    }
    await cancelStale(keepKey);
    if (a.choice === "ertelendi") proposals.push({ type: "appointment_create", question_id: q.id, label: `Yeni ${T.lc("appointment")} tarihi ekle`,
      apply: { method: "POST", path: "/api/appointments", body: { type: c.type || T.get("visit"), ...(c.customer_name ? { customer_name: c.customer_name } : {}), ...(c.customer_phone ? { customer_phone: c.customer_phone } : {}), ...(c.offer_id ? { offer_id: c.offer_id } : {}), ...(c.project_id ? { project_id: c.project_id } : {}) }, needs: ["scheduled_at"] } });
  } else if (q.kind === "money") {
    if (a.choice === "tahsilat") {
      const body = a.amount_kurus ? { amount: a.amount_kurus / 100, paid_at: ymdAt(date, "12:00").toISOString() } : { paid_at: ymdAt(date, "12:00").toISOString() };
      proposals.push({ type: "payment_create", question_id: q.id, label: `${T.cap("payment")} ekle`, amount_kurus: a.amount_kurus || null, project_id: a.project_id || null,
        apply: a.project_id ? { method: "POST", path: `/api/projects/${a.project_id}/payments`, body: { ...body, method: "Nakit" }, needs: a.amount_kurus ? [] : ["amount"] } : { method: "POST", path: "/api/projects/:project_id/payments", body: { ...body, method: "Nakit" }, needs: ["project_id", ...(a.amount_kurus ? [] : ["amount"])] } });
    } else if (a.choice === "gider") {
      proposals.push({ type: "expense_create", question_id: q.id, label: `${T.cap("expense")} ekle`, amount_kurus: a.amount_kurus || null,
        apply: { method: "POST", path: "/api/expenses", body: { category: a.category || "Diğer", ...(a.amount_kurus ? { amount: a.amount_kurus / 100 } : {}), expense_date: ymdAt(date, "12:00").toISOString(), ...(a.project_id ? { project_id: a.project_id } : {}) }, needs: a.amount_kurus ? [] : ["amount"] } });
    }
  } else if (q.kind === "stage") {
    if (a.choice === "evet") proposals.push({ type: "project_stage", question_id: q.id, project_id: c.project_id, from: c.from, to: c.to, label: `Aşamayı "${c.to}" yap`, apply: { method: "PATCH", path: `/api/projects/${c.project_id}/stage`, body: { stage: c.to } } });
  } else if (q.kind === "cost") {
    const p = facts.context.params([c.project_id, ctx.orgId]);
    const ok = await db.query(`SELECT p.id FROM projects p WHERE p.id = $1 AND p.org_id = $2${facts.context.ownerClause(ctx, "p", "project", p, "biz")}`, p.arr);
    if (!ok.rows[0]) throw Object.assign(new Error("Bu işe erişiminiz yok."), { status: 403 });
    if (a.choice === "tamam") {
      await db.query("UPDATE projects SET cost_confirmed_at = COALESCE(cost_confirmed_at, $2) WHERE id = $1", [c.project_id, clock.now()]);
      applied.push({ type: "cost_confirmed", project_id: c.project_id });
    } else {
      const key = `${keyBase}:eksik`;
      await db.query(`INSERT INTO followups (org_id, user_id, kind, title, due_date, project_id, source, source_key) VALUES ($1,$2,'bilgi',$3,$4::date,$5,'kapanis',$6) ON CONFLICT (user_id, source_key) WHERE source_key IS NOT NULL DO NOTHING`,
        [ctx.orgId, user.id, `Masrafları tamamla (${q.text.split(" için")[0]})`, clock.addDays(date, 1), c.project_id, key]);
      applied.push({ type: "followup", kind: "bilgi", due_date: clock.addDays(date, 1) });
    }
  } else if (q.kind === "tomorrow" && a.choice === "hatirlat") {
    const r = await reminderSvc.createSystem({ userId: user.id, orgId: ctx.orgId, title: `Yarın ${T.n(c.count, "appointment")}: hazırlık`, remindAt: ymdAt(tomorrowStr(date), "08:00"), source: "brifing", sourceKey: `${keyBase}`, note: c.first_time ? `İlk: ${c.first_time}` : null });
    applied.push({ type: "reminder", id: r.reminder ? r.reminder.id : null, created: r.created });
  }
  return { applied, proposals };
}

/** POST /closure/answers */
async function submit(user, body, { orgId, now = clock.now() }) {
  const date = (body && body.date) || clock.istanbulDateStr(now);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return { error: "date YYYY-MM-DD olmalı." };
  if (date > clock.addDays(clock.istanbulDateStr(now), 0)) return { error: "Gelecek günün kapanışı yapılamaz." };
  if (date < clock.addDays(clock.istanbulDateStr(now), -3)) return { error: "Yalnız son 3 günün kapanışı yanıtlanabilir." };
  const { row, ctx, T } = await ensureLog(user, { date, orgId, now });
  const v = validate(body, row);
  if (v.error) return { error: v.error };

  const applied = [], proposals = [];
  const answers = { ...(row.answers || {}) };
  for (const { q, a } of v.answers) {
    const r = await applyOne(ctx, T, user, date, q, a);
    applied.push(...r.applied.map((x) => ({ question_id: q.id, ...x })));
    proposals.push(...r.proposals);
    answers[q.id] = { ...a, skip_key: q.skip_key || null, answered_at: now.toISOString(), applied: r.applied };
  }
  const qs = row.questions || [];
  const answeredN = qs.filter((q) => answers[q.id] && !answers[q.id].skipped).length;
  const doneN = qs.filter((q) => answers[q.id]).length;
  const completeness = qs.length ? Math.round((answeredN * 100) / qs.length) : 100;
  let status = row.status;
  if (v.finish || doneN === qs.length) status = answeredN === 0 && qs.length > 0 ? "skipped" : "done";
  else if (doneN > 0 || v.free_note) status = "partial";
  const prevProposals = (row.summary && row.summary.proposals) || [];
  const mergedProposals = [...prevProposals.filter((p) => !v.answers.some((x) => x.q.id === p.question_id)), ...proposals];
  await db.query(
    `UPDATE daily_logs SET answers = $3, free_note = COALESCE($4, free_note), status = $5, completeness = $6,
            closed_at = CASE WHEN $5 IN ('done','skipped') THEN COALESCE(closed_at, $7) ELSE closed_at END, summary = COALESCE(summary,'{}'::jsonb) || $8::jsonb
      WHERE user_id = $1 AND log_date = $2::date`,
    [user.id, date, JSON.stringify(answers), v.free_note === undefined ? null : v.free_note, status, completeness, now, JSON.stringify({ proposals: mergedProposals })]);
  const fresh = await readLog(user.id, date);
  const card = await summaryCard(ctx, T, fresh);
  await db.query(`UPDATE daily_logs SET summary = summary || $2::jsonb WHERE id = $1`, [fresh.id, JSON.stringify({ card })]);
  await briefStore.save({ orgId: ctx.orgId, userId: user.id, kind: "evening", periodStart: date, title: `Gün sonu özeti — ${tr.formatDate(date)}`, bodyText: card.text, data: { v: 1, kind: "evening", ...card }, generatedBy: "job", now });
  const log = present({ ...fresh, summary: { proposals: mergedProposals } }, card, ctx);
  return { applied, closure_proposals: mergedProposals, log, summary_card: card };
}

module.exports = { ensureLog, getToday, submit, summaryCard, validate, readLog, NEXT_STAGE: questions.NEXT_STAGE };
