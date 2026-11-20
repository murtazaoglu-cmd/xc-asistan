/**
 * Komut çubuğu servisi: metin → (cevap | onay kartı | netleştirme). YAZMA hiçbir zaman doğrudan uygulanmaz:
 *   komut → ai_actions('onerildi') kartı → kullanıcı onaylar → mevcut REST uçları aynı yetkiyle çağrılır → 'uygulandi' (+ 10 dk geri alma).
 * Yasak (R3): silme, rol/yetki değişikliği, mesaj gönderme, teklif tutarı değiştirme → hiçbir koşulda çalıştırılmaz.
 * LLM yoktur; tüm sayılar/metinler kodla üretilir.
 */
const crypto = require("crypto");
const db = require("../../db");
const clock = require("../clock");
const settings = require("../settings");
const { orgIdForUser } = require("../org");
const { logAction } = require("../audit");
const { financeOwnerId } = require("../../middleware/access");
const { parseCommand, MAX_TEXT } = require("./parser");
const { customerPool, roleAllows, WRITE_INTENTS } = require("./scope");
const { BUILDERS, EDITABLE, ALL_CHOICE_KEYS, validateEdit, typeLabel, categoryLabel, toKurusSafe } = require("./builders");
const reads = require("./reads");
const { callApi } = require("../exec");
const { clean } = require("./text");

const UNDO_WINDOW_MS = Math.max(Number(process.env.ASSISTANT_UNDO_WINDOW_SEC) || 600, 5) * 1000;
const CARD_TTL_MS = 24 * 3600 * 1000;
const RAW_TEXT_DAYS = Math.max(Number(process.env.ASSISTANT_RAW_TEXT_DAYS) || 30, 1);
const DEDUPE_SEC = 60;
const RISK = { "reminder.create": "R1", "note.add": "R1" };

class HttpError extends Error {
  constructor(status, message, extra) { super(message); this.status = status; this.expose = true; this.extra = extra || {}; }
}

const REFUSALS = {
  delete: "Silme işlemlerini komut çubuğundan yapamam; ilgili ekrandan elle silin.",
  role_change: "Kullanıcı rolü, yetki ve şifre değişikliklerini komut çubuğundan yapamam; Kullanıcılar ekranından yapın.",
  send_message: "Müşteriye mesaj/e-posta göndermeyi komut çubuğundan yapamam; ilgili ekrandan kendiniz gönderin.",
  amount_change: "Teklif/proje tutarı değişikliğini komut çubuğundan yapamam; ilgili ekrandan yapın.",
};

const CHIPS = [
  { text: "Bugün ne var", roles: ["admin", "muhasebe", "ortak", "personel", "saha"] },
  { text: "Yarın randevularım", roles: ["admin", "muhasebe", "ortak", "personel", "saha"] },
  { text: "Bu ay ne kadar tahsilat var", roles: ["admin", "muhasebe", "ortak", "personel"] },
  { text: "Kimden alacağım var", roles: ["admin", "muhasebe", "ortak", "personel"] },
  { text: "Bu ay ne kadar gider var", roles: ["admin", "muhasebe", "ortak", "personel"] },
];
const chipsFor = (role) => CHIPS.filter((c) => c.roles.includes(role)).map((c) => c.text);

async function makeCtx(req) {
  const user = req.user;
  const cfg = await settings.buildConfig(user);
  const now = clock.now();
  return { req, user, cfg, terms: (cfg.sector_dictionary && cfg.sector_dictionary.terms) || {}, now, today: clock.istanbulDateStr(now), ledgerOwner: user.role === "saha" ? null : await financeOwnerId(user) };
}

// ---------------------------------------------------------------------------------------------------------------------
/** ayrıştırıcı çıktısı → taslak (builders'ın anlayacağı düz alanlar) */
function toDraft(parsed, ctx) {
  const p = parsed.params || {};
  const c = p.customer || {};
  const base = {};
  if (c.match) base.customer_key = c.match.key;
  else { if (c.query) base.customer_query = c.query; if (c.candidates && c.candidates.length) base.customer_options = c.candidates; }
  const kurus = (v) => (typeof v === "number" && Number.isFinite(v) ? Math.round(v * 100) : undefined);
  switch (parsed.intent) {
    case "appointment.create": return { ...base, date: p.date || null, time: p.time || null, type: p.type ? typeLabel(ctx.cfg, p.type) : null };
    case "appointment.reschedule": return { ...base, target_date: p.target_date || null, new_date: p.new_date || null, new_time: p.new_time || null, shift_days: Number.isInteger(p.shift_days) ? p.shift_days : null };
    case "appointment.cancel": return { ...base, target_date: p.date || null };
    case "reminder.create": return { ...base, title: p.title, date: p.date || null, time: p.time || null };
    case "payment.add": return { ...base, amount_kurus: kurus(p.amount), method: p.method, project_ref: p.project_ref || null, date: p.date || null };
    case "expense.add": return { ...base, amount_kurus: kurus(p.amount), category: p.category ? categoryLabel(ctx.cfg, p.category) : null, scope: p.scope, project_ref: p.project_ref || null, date: p.date || null };
    case "offer.status": return { ...base, status: p.status, offer_ref: p.offer_ref || null };
    case "note.add": return { ...base, text: p.text };
    default: return base;
  }
}

/** clarify `choices` / PATCH `fields` → taslağa uygula (beyaz liste + biçim doğrulaması). Hata: HttpError 400 */
function applyEdits(intent, draft, edits) {
  const allowed = EDITABLE[intent] || [];
  const out = { ...draft };
  for (const [k, v] of Object.entries(edits || {})) {
    if (!allowed.includes(k)) throw new HttpError(400, `“${String(k).slice(0, 30)}” alanı bu işlemde düzenlenemez.`);
    const err = validateEdit(k, v);
    if (err) throw new HttpError(400, err);
    if (k === "amount") { out.amount_kurus = toKurusSafe(v); continue; }
    if (k === "customer_key") { out.customer_key = v; delete out.customer_query; delete out.customer_options; continue; }
    if (v === "" || v === null) { delete out[k]; continue; }
    out[k] = v;
  }
  return out;
}

const canon = (o) => JSON.stringify(o, Object.keys(o).sort());
const hashOf = (intent, draft) => crypto.createHash("sha256").update(intent + "|" + canon(draft)).digest("hex");

function serialize(row, now = clock.now()) {
  const pv = row.preview || {};
  const ui = row.undo_info || {};
  return {
    id: row.id, origin: row.origin, intent: row.intent, risk: row.risk, status: row.status, text: row.raw_text || null,
    summary: pv.summary || "", fields: pv.fields || [], ambiguities: pv.ambiguities || [], warnings: pv.warnings || [],
    result: row.result || null, error: row.error || null,
    undo: { available: row.status === "uygulandi" && ui.undoable === true && ui.until && new Date(ui.until) > now, until: ui.until || null, reason: ui.undoable === false ? ui.reason || null : null },
    created_at: row.created_at, expires_at: row.expires_at, decided_at: row.decided_at, applied_at: row.applied_at, undone_at: row.undone_at,
  };
}

// ---------------------------------------------------------------------------------------------------------------------
/** POST /commands */
async function handleCommand(req, text, choices) {
  if (typeof text !== "string" || !text.trim()) throw new HttpError(400, "Komut metni (text) gerekli.");
  const raw = clean(text).trim();
  if (raw.length > MAX_TEXT) throw new HttpError(400, `Komut en çok ${MAX_TEXT} karakter olabilir.`);
  if (choices !== undefined && (choices === null || typeof choices !== "object" || Array.isArray(choices))) throw new HttpError(400, "choices bir nesne olmalı.");
  const ctx = await makeCtx(req);
  const user = ctx.user;
  const pool = await customerPool(user);
  const parsed = parseCommand(raw, { now: ctx.now, candidates: pool });
  const chips = chipsFor(user.role);

  if (parsed.intent === "forbidden") {
    await logAction({ req, action: "assistant.command.refused", entityType: "ai_command", data: { reason: parsed.params.reason } });
    return { kind: "answer", intent: "forbidden", refused: true, reason: parsed.params.reason, text: REFUSALS[parsed.params.reason] || "Bu işlemi komut çubuğundan yapamam.", confidence: parsed.confidence, chips };
  }
  if (parsed.intent === "unknown") {
    return { kind: "clarify", intent: "unknown", reason: "unknown", message: "Ne yapmak istediğinizi anlayamadım. Şunlardan birini deneyebilirsiniz.", questions: [], chips, confidence: parsed.confidence };
  }
  if (!roleAllows(parsed.intent, user.role)) {
    return { kind: "answer", intent: parsed.intent, refused: true, reason: "role", text: "Bu komutu kullanma yetkiniz yok.", confidence: parsed.confidence, chips };
  }

  // ---- okuma (R0)
  if (!WRITE_INTENTS.has(parsed.intent)) {
    // bulunamayan/belirsiz müşteri adı okuma sorgusunu bozmaz; yalnız sonuca not düşülür
    let out;
    switch (parsed.intent) {
      case "query.agenda": out = await reads.answerAgenda(user, parsed, ctx.today); break;
      case "query.appointments": out = await reads.answerAppointments(user, parsed, ctx.today); break;
      case "query.collections": out = await reads.answerCollections(user, parsed, ctx.today); break;
      case "query.expenses": out = await reads.answerExpenses(user, parsed, ctx.today); break;
      case "query.receivables": out = await reads.answerReceivables(user, parsed); break;
      case "customer.search": out = reads.answerCustomerSearch(parsed); break;
      default: throw new HttpError(500, "Sunucu hatası.");
    }
    return { kind: "answer", intent: parsed.intent, text: out.text, data: out.data, confidence: parsed.confidence, ambiguities: parsed.ambiguities, chips };
  }

  // ---- yazma (R1/R2): kart
  let draft = toDraft(parsed, ctx);
  draft = applyEdits(parsed.intent, draft, choices);
  const built = await BUILDERS[parsed.intent](ctx, draft);
  const clar = clarifyOf(parsed.intent, built, draft);
  if (clar) return { ...clar, confidence: parsed.confidence, chips };
  if (built.error) throw new HttpError(built.error.status, built.error.message);
  if (built.noop) return { kind: "answer", intent: parsed.intent, text: built.noop, confidence: parsed.confidence, chips };

  const warnings = [...built.warnings];
  if (parsed.confidence < 0.6) warnings.push("Emin değilim, lütfen kontrol edin.");
  const ambiguities = mergeAmb(built.ambiguities, parsed.ambiguities, ctx);

  const hash = hashOf(parsed.intent, built.draft);
  const dup = await db.query(`SELECT * FROM ai_actions WHERE user_id = $1 AND params_hash = $2 AND status = 'onerildi' AND created_at > now() - ($3 || ' seconds')::interval ORDER BY created_at DESC LIMIT 1`, [user.id, hash, String(DEDUPE_SEC)]);
  if (dup.rows[0]) return { kind: "action_card", deduped: true, confidence: parsed.confidence, action: serialize(dup.rows[0], ctx.now) };

  const orgId = await orgIdForUser(user.id);
  const now = ctx.now;
  const { rows } = await db.query(
    `INSERT INTO ai_actions (org_id, user_id, origin, intent, risk, raw_text, params, args, preview, params_hash, status, raw_expires_at, expires_at)
     VALUES ($1,$2,'command_bar',$3,$4,$5,$6,$7,$8,$9,'onerildi',$10,$11) RETURNING *`,
    [orgId, user.id, parsed.intent, RISK[parsed.intent] || "R2", raw, JSON.stringify(built.draft), JSON.stringify({ request: built.request, meta: built.meta || {} }),
     JSON.stringify({ summary: built.summary, fields: built.fields, ambiguities, warnings }), hash,
     new Date(now.getTime() + RAW_TEXT_DAYS * 86400000), new Date(now.getTime() + CARD_TTL_MS)]
  );
  await logAction({ req, orgId, action: "assistant.action.propose", entityType: "ai_action", entityId: rows[0].id, data: { intent: parsed.intent, origin: "command_bar" } });
  return { kind: "action_card", deduped: false, confidence: parsed.confidence, action: serialize(rows[0], now) };
}

/**
 * Hazır taslaktan kart üretir (yazışma önerisi kabulü gibi komut dışı kaynaklar için). origin: 'import' | 'system'.
 * Eksik/belirsiz alan → HttpError(422, mesaj, {questions}). Dönüş: serileştirilmiş kart.
 */
async function proposeDraft(req, intent, draft, { origin = "import", suggestionId = null, rawText = null } = {}) {
  if (!EDITABLE[intent]) throw new HttpError(400, "Desteklenmeyen işlem.");
  const ctx = await makeCtx(req);
  if (!roleAllows(intent, req.user.role)) throw new HttpError(403, "Bu işlem için yetkiniz yok.");
  const built = await BUILDERS[intent](ctx, draft);
  if (built.clarify) throw new HttpError(422, built.clarify.message, { questions: built.clarify.questions, draft: publicDraft(draft) });
  if (built.error) throw new HttpError(built.error.status, built.error.message);
  if (built.noop) throw new HttpError(409, built.noop);
  const hash = hashOf(intent, built.draft);
  const now = ctx.now;
  const { rows } = await db.query(
    `INSERT INTO ai_actions (org_id, user_id, origin, intent, risk, raw_text, params, args, preview, params_hash, status, suggestion_id, raw_expires_at, expires_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'onerildi',$11,$12,$13) RETURNING *`,
    [await orgIdForUser(req.user.id), req.user.id, origin, intent, RISK[intent] || "R2", rawText ? String(rawText).slice(0, 500) : null, JSON.stringify(built.draft),
     JSON.stringify({ request: built.request, meta: built.meta || {} }), JSON.stringify({ summary: built.summary, fields: built.fields, ambiguities: built.ambiguities, warnings: built.warnings }), hash,
     suggestionId, new Date(now.getTime() + RAW_TEXT_DAYS * 86400000), new Date(now.getTime() + CARD_TTL_MS)]
  );
  await logAction({ req, action: "assistant.action.propose", entityType: "ai_action", entityId: rows[0].id, data: { intent, origin } });
  return serialize(rows[0], now);
}

function clarifyOf(intent, built, draft) {
  if (!built.clarify) return null;
  return { kind: "clarify", intent, reason: built.clarify.reason || "ambiguous", message: built.clarify.message, questions: built.clarify.questions || [], draft: publicDraft(draft), retry: "POST /assistant/commands { text, choices:{ <field>: <value> } }" };
}
const publicDraft = (d) => { const o = { ...d }; delete o.customer_options; return o; };

function mergeAmb(a, parserAmb, ctx) {
  const out = [...(a || [])];
  for (const x of parserAmb || []) {
    if (["ampm", "same_weekday", "vague"].includes(x.kind) && !out.some((y) => y.field === x.field && y.kind === x.kind)) out.push(x);
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------
async function loadOwn(userId, id) {
  const { rows } = await db.query("SELECT * FROM ai_actions WHERE id = $1 AND user_id = $2", [id, userId]);
  if (!rows[0]) throw new HttpError(404, "İşlem önerisi bulunamadı.");
  let row = rows[0];
  if (row.status === "onerildi" && new Date(row.expires_at) <= clock.now()) {
    const u = await db.query("UPDATE ai_actions SET status = 'suresi_doldu', decided_at = now() WHERE id = $1 AND status = 'onerildi' RETURNING *", [id]);
    row = u.rows[0] || row;
  }
  return row;
}

async function getAction(user, id) { return serialize(await loadOwn(user.id, id)); }

async function listActions(user, { status, limit }) {
  const lim = Math.min(Math.max(parseInt(limit, 10) || 30, 1), 100);
  const params = [user.id]; let w = "user_id = $1";
  if (status) { params.push(String(status)); w += ` AND status = $${params.length}`; }
  params.push(lim);
  await db.query("UPDATE ai_actions SET status = 'suresi_doldu', decided_at = now() WHERE user_id = $1 AND status = 'onerildi' AND expires_at <= $2", [user.id, clock.now()]);
  const { rows } = await db.query(`SELECT * FROM ai_actions WHERE ${w} ORDER BY created_at DESC LIMIT $${params.length}`, params);
  return rows.map((r) => serialize(r));
}

/** Kartı düzenle (yalnız 'onerildi'): alanlar yeniden doğrulanır, önizleme yeniden üretilir */
async function editAction(req, id, fields) {
  const row = await loadOwn(req.user.id, id);
  if (row.status !== "onerildi") throw new HttpError(409, "Yalnız bekleyen öneriler düzenlenebilir.");
  if (!fields || typeof fields !== "object" || Array.isArray(fields) || !Object.keys(fields).length) throw new HttpError(400, "Düzenlenecek alan (fields) gerekli.");
  const ctx = await makeCtx(req);
  const draft = applyEdits(row.intent, row.params, fields);
  const built = await BUILDERS[row.intent](ctx, draft);
  if (built.clarify) throw new HttpError(422, built.clarify.message, { questions: built.clarify.questions });
  if (built.error) throw new HttpError(built.error.status, built.error.message);
  if (built.noop) throw new HttpError(409, built.noop);
  const hash = hashOf(row.intent, built.draft);
  const { rows } = await db.query(
    `UPDATE ai_actions SET params = $3, args = $4, preview = $5, params_hash = $6, expires_at = $7 WHERE id = $1 AND user_id = $2 AND status = 'onerildi' RETURNING *`,
    [id, req.user.id, JSON.stringify(built.draft), JSON.stringify({ request: built.request, meta: built.meta || {} }),
     JSON.stringify({ summary: built.summary, fields: built.fields, ambiguities: built.ambiguities, warnings: built.warnings }), hash, new Date(ctx.now.getTime() + CARD_TTL_MS)]
  );
  if (!rows[0]) throw new HttpError(409, "Öneri artık düzenlenemez.");
  await logAction({ req, action: "assistant.action.edit", entityType: "ai_action", entityId: id, data: { intent: row.intent, fields: Object.keys(fields) } });
  return serialize(rows[0], ctx.now);
}

const STATUS_MSG = { onaylandi: "İşlem şu anda uygulanıyor.", reddedildi: "Bu öneri reddedilmiş.", hata: "Bu öneri hata verdi; komutu yeniden verin.", geri_alindi: "Bu işlem geri alınmış.", suresi_doldu: "Önerinin süresi doldu; komutu yeniden verin." };

async function confirmAction(req, id, fields) {
  let row = await loadOwn(req.user.id, id);
  if (row.status === "uygulandi") return { action: serialize(row), replayed: true };
  if (row.status !== "onerildi") throw new HttpError(409, STATUS_MSG[row.status] || "Bu öneri onaylanamaz.");
  if (fields && Object.keys(fields).length) { await editAction(req, id, fields); row = await loadOwn(req.user.id, id); }

  const claim = await db.query("UPDATE ai_actions SET status = 'onaylandi', decided_at = now() WHERE id = $1 AND user_id = $2 AND status = 'onerildi' RETURNING *", [id, req.user.id]);
  if (!claim.rows[0]) {
    const again = await loadOwn(req.user.id, id);
    if (again.status === "uygulandi") return { action: serialize(again), replayed: true };
    throw new HttpError(409, STATUS_MSG[again.status] || "Bu öneri artık onaylanamaz.");
  }
  row = claim.rows[0];
  const ctx = await makeCtx(req);
  const fail = async (status, message, extra) => {
    const u = await db.query("UPDATE ai_actions SET status = 'hata', error = $2, applied_at = NULL WHERE id = $1 RETURNING *", [id, String(message).slice(0, 500)]);
    await logAction({ req, action: "assistant.action.error", entityType: "ai_action", entityId: id, data: { intent: row.intent, status } });
    throw new HttpError(status, message, { action: serialize(u.rows[0], ctx.now), ...(extra || {}) });
  };

  // taslağı güncel veriyle yeniden doğrula (bayat öneri güvenli olmaz)
  let built;
  try { built = await BUILDERS[row.intent](ctx, row.params); } catch (e) { return fail(500, "Sunucu hatası."); }
  if (built.clarify) return fail(409, built.clarify.message);
  if (built.error) return fail(built.error.status === 404 ? 404 : built.error.status, built.error.message);
  if (built.noop) return fail(409, built.noop);
  const rq = built.request;
  let result = null, undo = null;
  const until = new Date(ctx.now.getTime() + UNDO_WINDOW_MS).toISOString();

  if (rq.kind === "note") {
    const ins = await db.query(`INSERT INTO ai_notes (org_id, author, source_type, source_id, owner_user_id, body, phone_key) VALUES ($1,'user','command',$2,$3,$4,$5) RETURNING id`,
      [await orgIdForUser(req.user.id), id, req.user.id, rq.body, rq.phone_key]);
    result = { ref: { type: "note", id: ins.rows[0].id }, summary: "Not kaydedildi." };
    undo = { undoable: true, kind: "note_delete", note_id: ins.rows[0].id, until };
  } else {
    const r = await callApi(req, req.user, rq.method, rq.path, rq.body);
    if (!r.ok) {
      const msg = (r.body && r.body.error) || "İşlem uygulanamadı.";
      return fail([403, 404, 409].includes(r.status) ? r.status : (r.status >= 500 ? 502 : 422), msg);
    }
    const b = r.body || {};
    const meta = built.meta || {};
    switch (row.intent) {
      case "appointment.create": result = { ref: { type: "appointment", id: b.id }, summary: "Randevu oluşturuldu." }; undo = { undoable: true, kind: "rest", method: "DELETE", path: `/appointments/${b.id}` }; break;
      case "appointment.reschedule": result = { ref: { type: "appointment", id: row.params.appointment_id }, summary: "Randevu ertelendi." }; undo = { undoable: !!meta.old_at, kind: "rest", method: "PATCH", path: rq.path, body: { scheduled_at: meta.old_at } }; break;
      case "appointment.cancel": result = { ref: { type: "appointment", id: row.params.appointment_id }, summary: "Randevu iptal edildi." }; undo = { undoable: true, kind: "rest", method: "PATCH", path: rq.path, body: { status: meta.old_status || "beklemede" } }; break;
      case "reminder.create": result = { ref: { type: "reminder", id: b.id }, summary: "Hatırlatma kuruldu." }; undo = { undoable: true, kind: "rest", method: "DELETE", path: `/reminders/${b.id}` }; break;
      case "payment.add": result = { ref: { type: "payment", id: b.id, project_id: row.params.project_id }, summary: "Ödeme kaydedildi." }; undo = { undoable: true, kind: "rest", method: "DELETE", path: `/projects/payments/${b.id}` }; break;
      case "expense.add": result = { ref: { type: "expense", id: b.id }, summary: "Gider kaydedildi." }; undo = { undoable: true, kind: "rest", method: "DELETE", path: `/expenses/${b.id}` }; break;
      case "offer.status": result = { ref: { type: "offer", id: row.params.offer_id }, summary: "Teklif durumu güncellendi." }; undo = meta.undoable === false ? { undoable: false, reason: "Kabul edilen teklif (proje oluşur) komuttan geri alınamaz; Projeler/Teklifler ekranından düzeltin." } : { undoable: true, kind: "rest", method: "PATCH", path: rq.path, body: { status: meta.old_status } }; break;
      default: result = { ref: null, summary: "Uygulandı." };
    }
    if (undo) undo.until = until;
  }
  const done = await db.query("UPDATE ai_actions SET status = 'uygulandi', result = $2, undo_info = $3, applied_at = now(), error = NULL WHERE id = $1 RETURNING *", [id, JSON.stringify(result), JSON.stringify(undo)]);
  await logAction({ req, action: "assistant.action.apply", entityType: "ai_action", entityId: id, data: { intent: row.intent, ref: result && result.ref } });
  return { action: serialize(done.rows[0], ctx.now), replayed: false };
}

async function rejectAction(req, id) {
  const row = await loadOwn(req.user.id, id);
  if (row.status === "reddedildi") return serialize(row);
  if (row.status !== "onerildi") throw new HttpError(409, STATUS_MSG[row.status] || "Bu öneri reddedilemez.");
  const { rows } = await db.query("UPDATE ai_actions SET status = 'reddedildi', decided_at = now() WHERE id = $1 AND user_id = $2 AND status = 'onerildi' RETURNING *", [id, req.user.id]);
  if (!rows[0]) throw new HttpError(409, "Öneri artık reddedilemez.");
  await logAction({ req, action: "assistant.action.reject", entityType: "ai_action", entityId: id, data: { intent: row.intent } });
  return serialize(rows[0]);
}

async function undoAction(req, id) {
  let row = await loadOwn(req.user.id, id);
  if (row.status === "geri_alindi") return serialize(row);
  if (row.status !== "uygulandi") throw new HttpError(409, "Yalnız uygulanmış işlemler geri alınabilir.");
  const ui = row.undo_info || {};
  if (!ui.undoable) throw new HttpError(409, ui.reason || "Bu işlem geri alınamaz.");
  if (!ui.until || new Date(ui.until) <= clock.now()) throw new HttpError(409, "Geri alma süresi doldu.");
  const claim = await db.query("UPDATE ai_actions SET status = 'geri_alindi', undone_at = now() WHERE id = $1 AND user_id = $2 AND status = 'uygulandi' RETURNING *", [id, req.user.id]);
  if (!claim.rows[0]) { const a = await loadOwn(req.user.id, id); if (a.status === "geri_alindi") return serialize(a); throw new HttpError(409, "İşlem artık geri alınamaz."); }
  const revert = async (msg, status) => {
    await db.query("UPDATE ai_actions SET status = 'uygulandi', undone_at = NULL WHERE id = $1", [id]);
    throw new HttpError(status, msg);
  };
  if (ui.kind === "note_delete") {
    await db.query("DELETE FROM ai_notes WHERE id = $1 AND owner_user_id = $2", [ui.note_id, req.user.id]);
  } else {
    const r = await callApi(req, req.user, ui.method, ui.path, ui.body);
    // silinmiş kayıt zaten yok → geri alma amacı sağlanmış sayılır
    if (!r.ok && !(r.status === 404 && ui.method === "DELETE")) return revert((r.body && r.body.error) || "Geri alınamadı.", [403, 404, 409].includes(r.status) ? r.status : 422);
  }
  await logAction({ req, action: "assistant.action.undo", entityType: "ai_action", entityId: id, data: { intent: row.intent } });
  return serialize((await loadOwn(req.user.id, id)));
}

module.exports = { proposeDraft, handleCommand, getAction, listActions, editAction, confirmAction, rejectAction, undoAction, serialize, HttpError, chipsFor, UNDO_WINDOW_MS };
