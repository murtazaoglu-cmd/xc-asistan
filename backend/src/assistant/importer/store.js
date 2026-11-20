/**
 * Yazışma/not/öneri/rıza kayıtları — kapsam kuralı: kayıt SAHİBİ (owner_user_id / user_id) görür; admin işletme veri sorumlusu olarak hepsini görür.
 * Müşteri kartı uçları ayrıca müşteri havuzu kapsamını (scope.customerPool) doğrular: ortak B, ortak A'nın müşterisine ait kart/yazışma/not alamaz (404).
 */
const db = require("../../db");
const clock = require("../clock");
const { orgIdForUser } = require("../org");
const { logAction } = require("../audit");
const { poolEntry, tail10, customerPool, roleAllows } = require("../command/scope");
const { ImportError } = require("./service");
const svc = require("../command/service");
const { typeLabel } = require("../command/builders");
const settings = require("../settings");

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isAdmin = (u) => u.role === "admin";
const lim = (v, d = 50, max = 200) => Math.min(Math.max(parseInt(v, 10) || d, 1), max);
const off = (v) => Math.max(parseInt(v, 10) || 0, 0);
const trunc = (s, n) => (s == null ? null : String(s).length > n ? String(s).slice(0, n - 1) + "…" : String(s));
const SUG_TTL = 30 * 86400000;

/** WHERE parçası: kayıt sahibi (admin hepsi). col: sahip sütunu; params'a ekler */
function ownerWhere(user, col, params) {
  if (isAdmin(user)) return "TRUE";
  params.push(user.id); return `${col} = $${params.length}`;
}

async function needCustomer(user, key) {
  const e = await poolEntry(user, String(key || ""));
  if (!e) throw new ImportError(404, "Müşteri bulunamadı.");
  return e;
}
const bad = (m) => new ImportError(400, m);

// ---------- yazışmalar ----------
const convCols = "c.id, c.source, c.title, c.phone_key, c.customer_id, c.offer_id, c.project_id, c.is_group, c.owner_sender, c.first_message_at, c.last_message_at, c.message_count, c.retention_until, c.created_at, c.participants";

async function listConversations(user, { customerKey, limit, offset }) {
  const params = []; const w = [ownerWhere(user, "c.owner_user_id", params)];
  if (customerKey) { const e = await needCustomer(user, customerKey); params.push(e.key); w.push(`c.phone_key = $${params.length}`); }
  params.push(lim(limit, 30, 100), off(offset));
  const { rows } = await db.query(
    `SELECT ${convCols},
       (SELECT COUNT(*)::int FROM ai_suggestions s WHERE s.conversation_id = c.id AND s.status = 'beklemede') AS pending_suggestions
     FROM conversations c WHERE ${w.join(" AND ")} ORDER BY c.last_message_at DESC NULLS LAST LIMIT $${params.length - 1} OFFSET $${params.length}`, params);
  return rows;
}

async function loadConv(user, id) {
  if (!UUID.test(String(id))) throw bad("Geçersiz kimlik.");
  const params = [id]; const ow = ownerWhere(user, "c.owner_user_id", params);
  const { rows } = await db.query(`SELECT ${convCols} FROM conversations c WHERE c.id = $1 AND ${ow}`, params);
  if (!rows[0]) throw new ImportError(404, "Yazışma bulunamadı.");
  return rows[0];
}

async function getConversation(user, id) {
  const c = await loadConv(user, id);
  const last = await db.query("SELECT role, sender, kind, content, sent_at FROM conversation_messages WHERE conversation_id = $1 AND kind = 'text' ORDER BY sent_at DESC LIMIT 3", [id]);
  return { ...c, last_messages: last.rows.reverse().map((m) => ({ role: m.role, sender: m.sender, text: trunc(m.content, 200), at: m.sent_at })) };
}

async function listMessages(user, id, { limit, before }) {
  await loadConv(user, id);
  const params = [id]; let w = "conversation_id = $1";
  if (before) { const b = new Date(before); if (Number.isNaN(b.getTime())) throw bad("Geçersiz before."); params.push(b); w += ` AND sent_at < $${params.length}`; }
  const l = lim(limit, 50, 200); params.push(l + 1);
  const { rows } = await db.query(`SELECT id, role, sender, kind, content, sent_at, redacted FROM conversation_messages WHERE ${w} ORDER BY sent_at DESC, id DESC LIMIT $${params.length}`, params);
  const page = rows.slice(0, l);
  return { items: page.reverse(), next_before: rows.length > l ? page[0].sent_at : null };
}

async function deleteConversation(req, id) {
  const c = await loadConv(req.user, id);
  const cnt = await db.query("SELECT COUNT(*)::int n FROM conversation_messages WHERE conversation_id = $1", [id]);
  await db.query("DELETE FROM conversations WHERE id = $1", [id]);
  await logAction({ req, action: "assistant.conversation.delete", entityType: "conversation", entityId: id, data: { messages: cnt.rows[0].n, phone_key_set: !!c.phone_key } });
  return { deleted: true, messages: cnt.rows[0].n };
}

/** Yazışmayı müşteri/teklif/proje ile ilişkilendir (kapsam doğrulamalı) */
async function patchConversation(req, id, body) {
  const user = req.user; const c = await loadConv(user, id); const b = body || {};
  const sets = [], params = [id]; const add = (col, v) => { params.push(v); sets.push(`${col} = $${params.length}`); };
  if (b.title !== undefined) { if (typeof b.title !== "string" || !b.title.trim() || b.title.length > 120) throw bad("Geçersiz başlık."); add("title", b.title.trim()); }
  if (b.customer_key !== undefined) {
    if (b.customer_key === null) add("phone_key", null);
    else { const e = await needCustomer(user, b.customer_key); add("phone_key", e.key); }
  }
  for (const [k, table, kind] of [["offer_id", "offers", "offer"], ["project_id", "projects", "project"]]) {
    if (b[k] === undefined) continue;
    if (b[k] === null) { add(k, null); continue; }
    const { scopeClause } = require("../../middleware/ownership");
    const sc = scopeClause(user, "t", kind, 2);
    const r = UUID.test(String(b[k])) ? await db.query(`SELECT t.id FROM ${table} t WHERE t.id = $1 ${sc.clause}`, [b[k], ...sc.params]) : { rows: [] };
    if (!r.rows[0]) throw new ImportError(404, kind === "offer" ? "Teklif bulunamadı ya da erişiminiz yok." : "Proje bulunamadı ya da erişiminiz yok.");
    add(k, b[k]);
  }
  if (!sets.length) throw bad("Değiştirilecek alan yok.");
  await db.query(`UPDATE conversations SET ${sets.join(", ")} WHERE id = $1`, params);
  await logAction({ req, action: "assistant.conversation.patch", entityType: "conversation", entityId: id, data: { fields: Object.keys(b) } });
  return getConversation(user, id);
}

// ---------- notlar ----------
const noteCols = "n.id, n.author, n.source_type, n.body, n.tags, n.phone_key, n.offer_id, n.project_id, n.conversation_id, n.source_message_id, n.status, n.created_at, n.updated_at";
function cleanTags(t) {
  if (t === undefined) return undefined;
  if (!Array.isArray(t) || t.length > 12) throw bad("etiketler en çok 12 öğeli bir dizi olmalı.");
  return [...new Set(t.map((x) => String(x).toLowerCase().replace(/[^a-z0-9çğıöşü_-]/gi, "").slice(0, 24)).filter(Boolean))];
}
async function listNotes(user, { customerKey, conversationId, q, limit, offset }) {
  const params = []; const w = ["n.status = 'active'", ownerWhere(user, "n.owner_user_id", params)];
  if (customerKey) { const e = await needCustomer(user, customerKey); params.push(e.key); w.push(`n.phone_key = $${params.length}`); }
  if (conversationId) { if (!UUID.test(String(conversationId))) throw bad("Geçersiz conversation_id."); params.push(conversationId); w.push(`n.conversation_id = $${params.length}`); }
  if (q) { params.push("%" + String(q).slice(0, 80).replace(/[%_\\]/g, "\\$&") + "%"); w.push(`n.body ILIKE $${params.length}`); }
  params.push(lim(limit, 50, 200), off(offset));
  const { rows } = await db.query(`SELECT ${noteCols} FROM ai_notes n WHERE ${w.join(" AND ")} ORDER BY n.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`, params);
  return rows;
}
async function createNote(req, b) {
  const user = req.user; b = b || {};
  if (typeof b.body !== "string" || !b.body.trim() || b.body.length > 4000) throw bad("Not metni (body) 1–4000 karakter olmalı.");
  const tags = cleanTags(b.tags) || [];
  let key = null;
  if (b.customer_key) key = (await needCustomer(user, b.customer_key)).key;
  const { rows } = await db.query(
    `INSERT INTO ai_notes (org_id, author, source_type, owner_user_id, body, tags, phone_key) VALUES ($1,'user','manual',$2,$3,$4,$5) RETURNING id`,
    [await orgIdForUser(user.id), user.id, b.body.trim(), tags, key]);
  await logAction({ req, action: "assistant.note.create", entityType: "ai_note", entityId: rows[0].id });
  return getNote(user, rows[0].id);
}
async function getNote(user, id) {
  if (!UUID.test(String(id))) throw bad("Geçersiz kimlik.");
  const params = [id]; const ow = ownerWhere(user, "n.owner_user_id", params);
  const { rows } = await db.query(`SELECT ${noteCols} FROM ai_notes n WHERE n.id = $1 AND ${ow}`, params);
  if (!rows[0]) throw new ImportError(404, "Not bulunamadı.");
  return rows[0];
}
async function patchNote(req, id, b) {
  const n = await getNote(req.user, id); b = b || {};
  const sets = [], params = [id]; const add = (c, v) => { params.push(v); sets.push(`${c} = $${params.length}`); };
  if (b.body !== undefined) { if (typeof b.body !== "string" || !b.body.trim() || b.body.length > 4000) throw bad("Not metni 1–4000 karakter olmalı."); add("body", b.body.trim()); }
  if (b.tags !== undefined) add("tags", cleanTags(b.tags));
  if (b.status !== undefined) { if (!["active", "dismissed"].includes(b.status)) throw bad("Geçersiz durum."); add("status", b.status); }
  if (!sets.length) throw bad("Değiştirilecek alan yok.");
  await db.query(`UPDATE ai_notes SET ${sets.join(", ")}, updated_at = now() WHERE id = $1`, params);
  await logAction({ req, action: "assistant.note.update", entityType: "ai_note", entityId: n.id });
  return getNote(req.user, id);
}
async function deleteNote(req, id) {
  const n = await getNote(req.user, id);
  await db.query("DELETE FROM ai_notes WHERE id = $1", [n.id]);
  await logAction({ req, action: "assistant.note.delete", entityType: "ai_note", entityId: n.id });
  return { deleted: true };
}

// ---------- öneriler ----------
const SUG_STATUSES = ["beklemede", "kabul", "red", "suresi_doldu"];
const SUG_KINDS = ["not", "hatirlatma", "randevu", "gorev"];
async function listSuggestions(user, q) {
  const params = []; const w = [ownerWhere(user, "s.user_id", params)];
  const status = q.status || "beklemede";
  if (status !== "all") { if (!SUG_STATUSES.includes(status)) throw bad("Geçersiz status."); params.push(status); w.push(`s.status = $${params.length}`); }
  if (q.kind) { if (!SUG_KINDS.includes(q.kind)) throw bad("Geçersiz kind."); params.push(q.kind); w.push(`s.kind = $${params.length}`); }
  if (q.conversation_id) { if (!UUID.test(String(q.conversation_id))) throw bad("Geçersiz conversation_id."); params.push(q.conversation_id); w.push(`s.conversation_id = $${params.length}`); }
  if (q.customer_key) { const e = await needCustomer(user, q.customer_key); params.push(e.key); w.push(`c.phone_key = $${params.length}`); }
  if (status === "beklemede") w.push("s.expires_at > now()");
  params.push(lim(q.limit, 50, 200), off(q.offset));
  const { rows } = await db.query(
    `SELECT s.id, s.kind, s.status, s.payload, s.confidence, s.expires_at, s.created_at, s.decided_at, s.action_id, s.conversation_id, c.title AS conversation_title, c.phone_key,
            m.id AS msg_id, m.sent_at AS msg_at, m.role AS msg_role, m.sender AS msg_sender, m.content AS msg_text, m.redacted AS msg_redacted
       FROM ai_suggestions s JOIN conversations c ON c.id = s.conversation_id LEFT JOIN conversation_messages m ON m.id = s.source_message_id
      WHERE ${w.join(" AND ")} ORDER BY s.created_at DESC, s.id LIMIT $${params.length - 1} OFFSET $${params.length}`, params);
  return rows.map(serSug);
}
function serSug(r) {
  return { id: r.id, kind: r.kind, status: r.status, payload: r.payload, confidence: r.confidence === null ? null : Number(r.confidence), expires_at: r.expires_at, created_at: r.created_at, decided_at: r.decided_at, action_id: r.action_id,
    conversation: { id: r.conversation_id, title: r.conversation_title, customer_key: r.phone_key },
    source_message: r.msg_id ? { id: r.msg_id, sent_at: r.msg_at, role: r.msg_role, sender: r.msg_sender, text: r.msg_redacted ? null : trunc(r.msg_text, 300), redacted: !!r.msg_redacted } : null };
}
async function loadSug(user, id) {
  if (!UUID.test(String(id))) throw bad("Geçersiz kimlik.");
  const params = [id]; const ow = ownerWhere(user, "s.user_id", params);
  const { rows } = await db.query(
    `SELECT s.*, c.title AS conversation_title, c.phone_key, c.customer_id, c.offer_id, c.project_id, m.id AS msg_id, m.sent_at AS msg_at, m.role AS msg_role, m.sender AS msg_sender, m.content AS msg_text, m.redacted AS msg_redacted
       FROM ai_suggestions s JOIN conversations c ON c.id = s.conversation_id LEFT JOIN conversation_messages m ON m.id = s.source_message_id WHERE s.id = $1 AND ${ow}`, params);
  if (!rows[0]) throw new ImportError(404, "Öneri bulunamadı.");
  return rows[0];
}
const ymdOk = (s) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s);

/** PATCH /suggestions/:id {status:'kabul'|'red', fields?} — kabul: not → not kaydı; hatırlatma → kart+uygula (R1); randevu → onay kartı (R2) */
async function decideSuggestion(req, id, body) {
  const user = req.user; const b = body || {};
  if (!["kabul", "red"].includes(b.status)) throw bad("status kabul ya da red olmalı.");
  const cur = await loadSug(user, id);
  if (cur.status === b.status) return { suggestion: serSug(cur), replayed: true };
  if (cur.status !== "beklemede") throw new ImportError(409, "Bu öneri zaten karara bağlanmış.");
  if (new Date(cur.expires_at) <= clock.now()) { await db.query("UPDATE ai_suggestions SET status = 'suresi_doldu', decided_at = now() WHERE id = $1 AND status = 'beklemede'", [id]); throw new ImportError(409, "Önerinin süresi doldu."); }
  if (b.fields !== undefined && (b.fields === null || typeof b.fields !== "object" || Array.isArray(b.fields))) throw bad("fields bir nesne olmalı.");
  const claim = await db.query("UPDATE ai_suggestions SET status = $2, decided_at = now() WHERE id = $1 AND status = 'beklemede' RETURNING id", [id, b.status]);
  if (!claim.rows[0]) { const again = await loadSug(user, id); return { suggestion: serSug(again), replayed: true }; }
  const undoClaim = () => db.query("UPDATE ai_suggestions SET status = 'beklemede', decided_at = NULL WHERE id = $1", [id]);
  if (b.status === "red") {
    await logAction({ req, action: "assistant.suggestion.reject", entityType: "ai_suggestion", entityId: id, data: { kind: cur.kind } });
    return { suggestion: serSug(await loadSug(user, id)) };
  }
  const f = b.fields || {}; const p = cur.payload || {};
  const inPool = cur.phone_key ? await poolEntry(user, cur.phone_key) : null;
  let out = {};
  try {
    if (cur.kind === "not" || cur.kind === "gorev") {
      let body_ = f.body !== undefined ? f.body : p.body;
      if (typeof body_ !== "string" || !body_.trim() || body_.length > 4000) throw bad("Not metni 1–4000 karakter olmalı.");
      const tags = f.tags !== undefined ? cleanTags(f.tags) : (Array.isArray(p.tags) ? cleanTags(p.tags) : []);
      const ins = await db.query(
        `INSERT INTO ai_notes (org_id, author, source_type, source_id, import_id, conversation_id, source_message_id, owner_user_id, body, tags, phone_key, customer_id, offer_id, project_id)
         VALUES ($1,'rule','import',$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,
        [await orgIdForUser(user.id), id, cur.import_id, cur.conversation_id, cur.source_message_id, user.id, body_.trim(), tags, cur.phone_key, cur.customer_id, cur.offer_id, cur.project_id]);
      out.note = await getNote(user, ins.rows[0].id);
    } else if (cur.kind === "hatirlatma") {
      const draft = { title: String(f.title !== undefined ? f.title : p.title || ""), date: f.date !== undefined ? f.date : p.date, time: f.time !== undefined ? f.time : p.time, ...(inPool ? { customer_key: inPool.key } : {}) };
      const card = await svc.proposeDraft(req, "reminder.create", draft, { origin: "import", suggestionId: id, rawText: null });
      await db.query("UPDATE ai_suggestions SET action_id = $2 WHERE id = $1", [id, card.id]);
      const done = await svc.confirmAction(req, card.id); // R1: kabul = onay; 10 dk geri alma açık
      out.action = done.action;
    } else if (cur.kind === "randevu") {
      const cfg = await settings.buildConfig(user);
      const draft = { date: f.date !== undefined ? f.date : p.date, time: f.time !== undefined ? f.time : p.time, type: f.type || typeLabel(cfg, p.type), ...(inPool ? { customer_key: inPool.key } : {}) };
      if (draft.time == null) delete draft.time;
      const card = await svc.proposeDraft(req, "appointment.create", draft, { origin: "import", suggestionId: id, rawText: null });
      await db.query("UPDATE ai_suggestions SET action_id = $2 WHERE id = $1", [id, card.id]);
      out.action = card; // R2: kullanıcı kartı ayrıca onaylar
    }
  } catch (e) { await undoClaim().catch(() => {}); throw e; }
  await logAction({ req, action: "assistant.suggestion.accept", entityType: "ai_suggestion", entityId: id, data: { kind: cur.kind } });
  return { suggestion: serSug(await loadSug(user, id)), ...out };
}

// ---------- müşteri kartı ----------
async function customerSummary(user, key) {
  const e = await needCustomer(user, key);
  const p1 = [e.key]; const ow1 = ownerWhere(user, "owner_user_id", p1);
  const p2 = [e.key]; const ow2 = ownerWhere(user, "s.user_id", p2);
  const [c, n, s, last] = await Promise.all([
    db.query(`SELECT COUNT(*)::int n, COALESCE(SUM(message_count),0)::int m, MAX(last_message_at) l FROM conversations WHERE phone_key = $1 AND ${ow1}`, p1),
    db.query(`SELECT COUNT(*)::int n FROM ai_notes WHERE phone_key = $1 AND status = 'active' AND ${ow1}`, p1),
    db.query(`SELECT COUNT(*)::int n FROM ai_suggestions s JOIN conversations c ON c.id = s.conversation_id WHERE c.phone_key = $1 AND s.status = 'beklemede' AND s.expires_at > now() AND ${ow2}`, p2),
    db.query(`SELECT m.role, m.sender, m.content, m.sent_at FROM conversation_messages m JOIN conversations c ON c.id = m.conversation_id WHERE c.phone_key = $1 AND m.kind = 'text' AND ${ow1.replace("owner_user_id", "c.owner_user_id")} ORDER BY m.sent_at DESC LIMIT 3`, p1),
  ]);
  return { customer: { key: e.key, name: e.name, phone: e.phone }, conversations: c.rows[0].n, messages: c.rows[0].m, last_message_at: c.rows[0].l, notes: n.rows[0].n, pending_suggestions: s.rows[0].n, last_messages: last.rows.reverse().map((m) => ({ role: m.role, sender: m.sender, text: trunc(m.content, 200), at: m.sent_at })) };
}

/** KVKK silme/unutulma: müşteriye bağlı bu kullanıcının yazışma + not + öneri + içe aktarma kayıtları (admin: hepsi) */
async function deleteCustomerData(req, key) {
  const e = await needCustomer(req.user, key);
  const p = [e.key]; const ow = ownerWhere(req.user, "owner_user_id", p);
  const convs = await db.query(`SELECT id, (SELECT COUNT(*)::int FROM conversation_messages m WHERE m.conversation_id = c.id) AS n FROM conversations c WHERE phone_key = $1 AND ${ow}`, p);
  const notes = await db.query(`DELETE FROM ai_notes WHERE phone_key = $1 AND ${ow} RETURNING id`, p);
  const ids = convs.rows.map((r) => r.id);
  if (ids.length) {
    await db.query("DELETE FROM conversation_imports WHERE conversation_id = ANY($1::uuid[])", [ids]); // katılımcı/ad bilgisi taşır
    await db.query("DELETE FROM conversations WHERE id = ANY($1::uuid[])", [ids]);
  }
  const out = { conversations: ids.length, messages: convs.rows.reduce((s, r) => s + r.n, 0), notes: notes.rowCount };
  await logAction({ req, action: "assistant.customer_data.delete", entityType: "customer", entityId: e.key, data: out });
  return { deleted: true, ...out };
}

// ---------- rıza kayıtları ----------
const CONSENT_KINDS = ["aydinlatma", "acik_riza", "veri_isleme_ack", "ticari_ileti"];
async function listConsents(user, q) {
  const params = []; const w = [ownerWhere(user, "user_id", params)];
  if (q.customer_key) { const e = await needCustomer(user, q.customer_key); params.push(e.key); w.push(`phone_key = $${params.length}`); }
  params.push(lim(q.limit, 50, 200));
  const { rows } = await db.query(`SELECT id, subject_type, phone_key, kind, text_version, granted, source, note, at, withdrawn_at FROM consents WHERE ${w.join(" AND ")} ORDER BY at DESC LIMIT $${params.length}`, params);
  return rows;
}
async function createConsent(req, b) {
  const user = req.user; b = b || {};
  if (!CONSENT_KINDS.includes(b.kind)) throw bad("kind aydinlatma | acik_riza | veri_isleme_ack | ticari_ileti olmalı.");
  if (typeof b.text_version !== "string" || !b.text_version.trim() || b.text_version.length > 40) throw bad("text_version gerekli (≤40).");
  if (b.note !== undefined && b.note !== null && (typeof b.note !== "string" || b.note.length > 500)) throw bad("note en çok 500 karakter.");
  let key = null;
  if (b.customer_key) key = (await needCustomer(user, b.customer_key)).key;
  if (!key) throw bad("customer_key gerekli (müşteri aydınlatma/rıza kaydı).");
  const { rows } = await db.query(
    `INSERT INTO consents (org_id, user_id, subject_type, phone_key, kind, text_version, granted, source, note) VALUES ($1,$2,'customer',$3,$4,$5,$6,'manual',$7) RETURNING id, subject_type, phone_key, kind, text_version, granted, source, note, at, withdrawn_at`,
    [await orgIdForUser(user.id), user.id, key, b.kind, b.text_version.trim(), b.granted !== false, b.note || null]);
  await logAction({ req, action: "assistant.consent.create", entityType: "consent", entityId: rows[0].id, data: { kind: b.kind } });
  return rows[0];
}
async function withdrawConsent(req, id) {
  if (!UUID.test(String(id))) throw bad("Geçersiz kimlik.");
  const params = [id]; const ow = ownerWhere(req.user, "user_id", params);
  const { rows } = await db.query(`UPDATE consents SET withdrawn_at = COALESCE(withdrawn_at, now()) WHERE id = $1 AND ${ow} RETURNING id, subject_type, phone_key, kind, text_version, granted, source, note, at, withdrawn_at`, params);
  if (!rows[0]) throw new ImportError(404, "Kayıt bulunamadı.");
  await logAction({ req, action: "assistant.consent.withdraw", entityType: "consent", entityId: id });
  return rows[0];
}

module.exports = { listConversations, getConversation, listMessages, deleteConversation, patchConversation, listNotes, createNote, getNote, patchNote, deleteNote, listSuggestions, decideSuggestion, customerSummary, deleteCustomerData, listConsents, createConsent, withdrawConsent, needCustomer };
