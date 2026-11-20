/**
 * Yazışma içe aktarma servisi: dosya/metin → güvenli ayrıştırma → ÖNİZLEME (staged) → onay → kalıcı yazışma + öneriler.
 * Veri yalnız bu sunucuda işlenir (dış servis yok). Dosya diske YAZILMAZ; zip içindeki adlar yol olarak kullanılmaz.
 */
const crypto = require("crypto");
const db = require("../../db");
const clock = require("../clock");
const { orgIdForUser } = require("../org");
const { logAction } = require("../audit");
const { scopeClause } = require("../../middleware/ownership");
const { parseWhatsAppText, titleFromFileName, normSender } = require("./whatsappParser");
const { extractChatText, ZipError } = require("./zipReader");
const { extractSuggestions } = require("./extractor");
const { customerPool, poolEntry, tail10 } = require("../command/scope");
const { tokenize } = require("../command/tokenize");
const { prepareCandidates, matchCustomers, decide } = require("../command/entities");
const { fold, clean } = require("../command/text");
const consent = require("./consent");
const retention = require("./retention");

class ImportError extends Error {
  constructor(status, message, extra) { super(message); this.status = status; this.expose = true; this.extra = extra || {}; }
}

const MAX_MESSAGES = Math.min(Math.max(Number(process.env.IMPORT_MAX_MESSAGES) || 50000, 100), 200000);
const MAX_TEXT_BYTES = 12 * 1024 * 1024;
const MAX_SHARE_CHARS = 200000;
const PREVIEW_TTL_MS = 24 * 3600 * 1000;
const SUGGESTION_TTL_MS = 30 * 86400000;
const HTML_SIG = /^\s*(<!doctype|<html|<\?xml|<svg|<script|<body|<head|<iframe|<\?php|%pdf)/i;

/** Görünen dosya adı: yol parçası/kontrol karakteri atılır, ≤120 (diske yazılmaz, yol olarak kullanılmaz) */
function safeLabel(name) {
  const base = String(name || "").replace(/\\/g, "/").split("/").pop();
  return clean(base).replace(/[<>"|?*\u0000-\u001f]/g, "").trim().slice(0, 120) || "sohbet";
}

function decodeText(buf) {
  if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) return buf.slice(2).toString("utf16le");
  if (buf.length >= 2 && buf[0] === 0xfe && buf[1] === 0xff) { const b = Buffer.from(buf.slice(2)); b.swap16(); return b.toString("utf16le"); }
  if (buf.slice(0, 65536).includes(0)) throw new ImportError(400, "Bu bir metin (sohbet) dosyası değil.");
  let text;
  try { text = new TextDecoder("utf-8", { fatal: true }).decode(buf); }
  catch { try { text = new TextDecoder("windows-1254").decode(buf); } catch { throw new ImportError(400, "Dosya kodlaması okunamadı."); } }
  return text;
}

/** Ham yükleme (Buffer) → {text, kind, bytes, name}. Tür uzantı + imza (magic bytes) ile doğrulanır. */
function readUpload(buf, filename) {
  if (!Buffer.isBuffer(buf) || buf.length === 0) throw new ImportError(400, "Dosya boş.");
  const ext = (/\.([A-Za-z0-9]{1,5})$/.exec(String(filename || "")) || [])[1];
  const lower = ext ? ext.toLowerCase() : "";
  if (lower !== "txt" && lower !== "zip") throw new ImportError(400, "Yalnız WhatsApp sohbet dışa aktarımı (.txt veya .zip) yüklenebilir.");
  const isZip = buf.length >= 4 && buf[0] === 0x50 && buf[1] === 0x4b && (buf[2] === 3 || buf[2] === 5);
  if (lower === "zip" && !isZip) throw new ImportError(400, "Dosya geçerli bir ZIP değil.");
  if (lower === "txt" && isZip) throw new ImportError(400, "Dosya uzantısı .txt ama içeriği ZIP; geçersiz.");
  let textBuf = buf, innerName = filename;
  if (isZip) {
    try { const r = extractChatText(buf); textBuf = r.text; innerName = r.name; }
    catch (e) { if (e instanceof ZipError) throw new ImportError(e.status || 400, e.message); throw e; }
  }
  if (textBuf.length > MAX_TEXT_BYTES) throw new ImportError(413, "Sohbet dosyası çok büyük.");
  const text = decodeText(textBuf);
  if (HTML_SIG.test(text.slice(0, 256))) throw new ImportError(400, "Dosya sohbet metni değil.");
  return { text, kind: isZip ? "zip" : "txt", bytes: buf.length, innerName };
}

// ---------- müşteri eşleme ----------
/** Katılımcı adları + başlık + telefonlar → havuzdaki müşteri adayları (telefon > ad). */
function matchCandidates(pool, { participants, title, forcedKey }) {
  const out = new Map();
  const put = (c, score, reason) => { const cur = out.get(c.key); if (!cur || cur.score < score) out.set(c.key, { key: c.key, name: c.name, phone: c.phone || null, score: Math.round(score * 100) / 100, reason }); };
  const byKey = new Map(pool.map((c) => [c.key, c]));
  if (forcedKey && byKey.has(forcedKey)) put(byKey.get(forcedKey), 1, "secildi");
  for (const p of participants) {
    const k = tail10(p.name);
    if (p.isPhone && k && byKey.has(k)) put(byKey.get(k), 1, "telefon");
  }
  const prepared = prepareCandidates(pool);
  const names = [...participants.filter((p) => !p.isPhone).map((p) => ({ n: p.name, r: "ad" })), ...(title ? [{ n: title, r: "baslik" }] : [])];
  for (const { n, r } of names) {
    const hits = matchCustomers(tokenize(String(n)), new Set(), prepared, { phase: "any" });
    for (const h of hits) if (h.score >= 0.7) put(h.cand, h.score, r);
  }
  return [...out.values()].sort((a, b) => b.score - a.score).slice(0, 6);
}

/** "Ben" tarafını tahmin et: başlıkla eşleşen katılımcının karşısındaki; ya da kullanıcının kendi adı */
function guessOwner(participants, { title, matchedName, userName }) {
  const real = participants.filter((p) => !p.isPhone || participants.length <= 2);
  if (participants.length === 2) {
    const ref = fold(matchedName || title || "");
    if (ref) {
      const cust = participants.find((p) => { const f = fold(p.name); return f && (ref.includes(f) || f.includes(ref) || f.split(" ")[0] === ref.split(" ")[0]); });
      if (cust) return participants.find((p) => p !== cust).name;
    }
  }
  const u = fold(userName || "");
  if (u) { const me = real.find((p) => fold(p.name) === u || (u.split(" ")[0] && fold(p.name).split(" ")[0] === u.split(" ")[0] && fold(p.name).length > 2 && participants.length <= 3)); if (me) return me.name; }
  return null;
}

const snippet = (t, n = 120) => (t == null ? null : (t.length > n ? t.slice(0, n - 1) + "…" : t));
const hashOf = (dedupeKey, n) => crypto.createHash("sha256").update(`${dedupeKey}#${n}`).digest("hex");

function rolesFor(messages, ownerSender, isGroup) {
  const me = ownerSender ? normSender(ownerSender) : null;
  // "ben" belirsizse ve grup değilse gönderen müşteri sayılır (tek mesaj paylaşımı); grupta kimlik belirsiz kalır
  return messages.map((m) => (me && normSender(m.sender) === me ? "owner" : (isGroup ? "unknown" : "customer")));
}

/** Öneri sayıları (önizleme için) — çıkarıcıyı gerçek kayıt olmadan çalıştırır */
function runExtractor(msgs, roles, customerName, now) {
  const input = msgs.map((m, i) => ({ role: roles[i], sender: m.sender, content: m.kind === "text" || m.kind === "location" ? m.text : null, sent_at: m.ts }));
  return { input, suggestions: extractSuggestions(input, { now, customerName }) };
}

// ---------- önizleme ----------
async function createPreview(req, { buf, filename, text: shareText, source, fields }) {
  const user = req.user;
  const f = fields || {};
  if (!(f.consent === true || f.consent === "true" || f.consent === "1" || f.consent === 1)) throw new ImportError(400, "İçe aktarmadan önce aydınlatma/rıza onayı gerekli (consent=true).", { notice: consent.NOTICE });
  if (String(f.consent_version || "") !== consent.VERSION) throw new ImportError(400, "Aydınlatma metni güncel değil; GET /assistant/imports/consent-notice ile güncel metni alıp yeniden onaylayın.", { notice: consent.NOTICE, required_version: consent.VERSION });
  const src = source === "share" ? "share" : "whatsapp_export";
  let text, kind, bytes, label;
  if (typeof shareText === "string") {
    if (!shareText.trim()) throw new ImportError(400, "Metin boş.");
    if (shareText.length > MAX_SHARE_CHARS) throw new ImportError(413, "Metin çok uzun.");
    text = shareText; kind = "txt"; bytes = Buffer.byteLength(shareText); label = safeLabel(f.title || "paylasilan-metin");
  } else {
    const up = readUpload(buf, filename);
    text = up.text; kind = up.kind; bytes = up.bytes; label = safeLabel(filename);
  }
  const sha = crypto.createHash("sha256").update(typeof shareText === "string" ? shareText : buf).digest("hex");
  const now = clock.now();
  let parsed = parseWhatsAppText(text, { maxMessages: MAX_MESSAGES });
  let singleMessage = false;
  if (!parsed.messages.length && src === "share") {
    // tek mesaj paylaşımı / pano: biçimsiz metin tek bir müşteri mesajı sayılır (gönderen bilinmez)
    const ts = now;
    parsed = { messages: [{ ts, localIso: ts.toISOString(), sender: "Paylaşılan mesaj", kind: "text", text: text.trim().slice(0, 8000), dedupeKey: `${ts.toISOString().slice(0, 16)}|paylasilan|text|${text.trim().slice(0, 200)}`, n: 1 }], stats: { platform: "unknown", locale: "", date_order: "dmy", time_format: "24h", messages: 1, system: 0, text: 1, media: 0, deleted: 0, location: 0, first_at: ts.toISOString(), last_at: ts.toISOString(), participants: [{ name: "Paylaşılan mesaj", count: 1, isPhone: false }], is_group: false, total_lines: 1, ignored_leading_lines: 0 }, warnings: ["single_message"] };
    singleMessage = true;
  }
  if (!parsed.messages.length) throw new ImportError(422, "Sohbet biçimi tanınamadı: WhatsApp “Sohbeti dışa aktar” (.txt/.zip) dosyası bekleniyor.");
  const st = parsed.stats;
  const title = safeLabel(f.title || titleFromFileName(filename || "") || "").replace(/^sohbet$/, "") || null;
  const pool = await customerPool(user);
  let forced = null;
  if (f.customer_key) { forced = await poolEntry(user, String(f.customer_key)); if (!forced) throw new ImportError(404, "Seçilen müşteri bulunamadı ya da erişiminiz yok."); }
  const candidates = matchCandidates(pool, { participants: st.participants, title: title, forcedKey: forced && forced.key });
  const top = candidates[0] && candidates[0].score >= 0.9 && (!candidates[1] || candidates[0].score - candidates[1].score >= 0.12) ? candidates[0] : null;
  const ownerSender = f.owner_sender ? String(f.owner_sender) : guessOwner(st.participants, { title, matchedName: top && top.name, userName: user.name });
  const roles = rolesFor(parsed.messages, ownerSender, st.is_group);
  const custName = (top && top.name) || (forced && forced.name) || title || "Müşteri";
  const ex = runExtractor(parsed.messages, roles, custName, now);
  const counts = { not: 0, hatirlatma: 0, randevu: 0 };
  for (const s of ex.suggestions) counts[s.kind] = (counts[s.kind] || 0) + 1;
  const dupFile = await db.query("SELECT id FROM conversation_imports WHERE user_id = $1 AND file_sha256 = $2 AND status = 'onaylandi' LIMIT 1", [user.id, sha]);

  const staged = { title, ownerGuess: ownerSender, customerKey: (forced && forced.key) || (top && top.key) || null, messages: parsed.messages.map((m) => ({ t: m.ts.toISOString(), s: m.sender, k: m.kind, x: m.text == null ? null : m.text, d: m.dedupeKey, n: m.n })) };
  const orgId = await orgIdForUser(user.id);
  const stats = { ...st, participants: st.participants };
  const client = await db.pool.connect();
  let row, consentId;
  try {
    await client.query("BEGIN");
    const c = await client.query(`INSERT INTO consents (org_id, user_id, subject_type, kind, text_version, granted, source, note) VALUES ($1,$2,'import','veri_isleme_ack',$3,true,'import',$4) RETURNING id`,
      [orgId, user.id, consent.VERSION, `Yazışma içe aktarma onayı (${kind})`]);
    consentId = c.rows[0].id;
    const ins = await client.query(
      `INSERT INTO conversation_imports (org_id, user_id, source, status, file_label, file_kind, file_bytes, file_sha256, stats, candidates, staged, consent_id, expires_at)
       VALUES ($1,$2,$3,'onizleme',$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id, expires_at, created_at`,
      [orgId, user.id, src, label, kind, bytes, sha, JSON.stringify(stats), JSON.stringify(candidates), JSON.stringify(staged), consentId, new Date(now.getTime() + PREVIEW_TTL_MS)]);
    row = ins.rows[0];
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
  await logAction({ req, orgId, action: "assistant.import.preview", entityType: "conversation_import", entityId: row.id, data: { kind, bytes, messages: st.messages, source: src } });

  const msgs = parsed.messages;
  return {
    id: row.id, status: "onizleme", source: src, file: { label, kind, bytes }, expires_at: row.expires_at,
    title, stats, participants: st.participants, is_group: !!st.is_group,
    suggested_owner_sender: ownerSender, candidates, customer: forced ? { key: forced.key, name: forced.name, phone: forced.phone } : (top ? { key: top.key, name: top.name, phone: top.phone } : null),
    already_imported: dupFile.rows.length > 0, single_message: singleMessage,
    warnings: [...parsed.warnings, ...(st.is_group ? ["group_chat_excluded_by_default"] : []), ...(dupFile.rows.length ? ["file_already_imported"] : [])],
    preview_messages: { first: msgs.slice(0, 3).map((m) => ({ at: m.ts, sender: m.sender, text: snippet(m.text) })), last: msgs.slice(-3).map((m) => ({ at: m.ts, sender: m.sender, text: snippet(m.text) })) },
    suggestion_counts: counts, consent: { id: consentId, version: consent.VERSION },
  };
}

// ---------- onay ----------
async function loadOwnImport(user, id, { forUpdate = false } = {}) {
  const { rows } = await db.query(`SELECT * FROM conversation_imports WHERE id = $1 AND ${user.role === "admin" ? "TRUE" : "user_id = $2"}`, user.role === "admin" ? [id] : [id, user.id]);
  if (!rows[0]) throw new ImportError(404, "İçe aktarma bulunamadı.");
  return rows[0];
}

async function checkLink(user, table, kind, id) {
  if (!id) return null;
  const sc = scopeClause(user, "t", kind, 2);
  const { rows } = await db.query(`SELECT t.id FROM ${table} t WHERE t.id = $1::uuid ${sc.clause}`, [String(id), ...sc.params]).catch(() => ({ rows: [] }));
  if (!rows[0]) throw new ImportError(404, kind === "offer" ? "Teklif bulunamadı ya da erişiminiz yok." : "Proje bulunamadı ya da erişiminiz yok.");
  return rows[0].id;
}

async function confirmImport(req, id, body) {
  const user = req.user, b = body || {};
  const imp = await loadOwnImport(user, id);
  if (imp.status === "onaylandi") {
    return { already: true, import: await getImport(user, id) };
  }
  if (imp.status !== "onizleme") throw new ImportError(409, "Bu içe aktarma onaylanamaz.");
  if (new Date(imp.expires_at) <= clock.now()) { await db.query("UPDATE conversation_imports SET status = 'suresi_doldu', staged = NULL, candidates = '[]' WHERE id = $1", [id]); throw new ImportError(409, "Önizlemenin süresi doldu; dosyayı yeniden yükleyin."); }
  const staged = imp.staged;
  if (!staged || !Array.isArray(staged.messages)) throw new ImportError(409, "Önizleme verisi yok; dosyayı yeniden yükleyin.");
  const stats = imp.stats || {};
  const participants = stats.participants || [];
  if (stats.is_group && !(b.include_group === true)) throw new ImportError(400, "Grup sohbetleri varsayılan olarak içe aktarılmaz; yine de almak için include_group=true gönderin.");
  const ownerSender = b.owner_sender != null ? String(b.owner_sender) : staged.ownerGuess;
  const needOwner = participants.length >= 2;
  if (needOwner && (!ownerSender || !participants.some((p) => normSender(p.name) === normSender(ownerSender)))) throw new ImportError(400, "owner_sender (yazışmada “ben” olan kişi) katılımcılardan biri olmalı.", { participants: participants.map((p) => p.name) });
  let cust = null;
  const ckey = Object.prototype.hasOwnProperty.call(b, "customer_key") ? b.customer_key : staged.customerKey; // null = müşteriye bağlama
  if (ckey) { cust = await poolEntry(user, String(ckey)); if (!cust) throw new ImportError(404, "Seçilen müşteri bulunamadı ya da erişiminiz yok."); }
  const offerId = await checkLink(user, "offers", "offer", b.offer_id);
  const projectId = await checkLink(user, "projects", "project", b.project_id);
  const title = (b.title ? safeLabel(b.title) : null) || (cust && cust.name) || staged.title || safeLabel(imp.file_label);
  const convoKey = cust ? `phone:${cust.key}` : `name:${fold(title)}`;
  const phoneKey = cust ? cust.key : null;
  const msgs = staged.messages.map((m) => ({ ts: new Date(m.t), sender: m.s, kind: m.k, text: m.x, dedupeKey: m.d, n: m.n }));
  const roles = rolesFor(msgs, needOwner ? ownerSender : null, !!stats.is_group);
  const now = clock.now();
  const orgId = await orgIdForUser(user.id);
  let customerRowId = null;
  if (cust) { const cr = await db.query("SELECT id FROM customers WHERE right(regexp_replace(phone,'[^0-9]','','g'),10) = $1 AND ($2::boolean OR owner_id = $3) LIMIT 1", [cust.key, user.role === "admin" || user.role === "muhasebe", user.id]); customerRowId = cr.rows[0] ? cr.rows[0].id : null; }
  const retentionUntil = new Date(now.getTime() + retention.RETENTION_DAYS() * 86400000);
  const rawExp = new Date(now.getTime() + retention.RAW_DAYS() * 86400000);

  const client = await db.pool.connect();
  let inserted = 0, convoId, sugInserted = 0, sugTotal = 0;
  try {
    await client.query("BEGIN");
    // çift onay yarışı: durum geçişi atomik
    const claim = await client.query("UPDATE conversation_imports SET status = 'onaylandi', confirmed_at = now() WHERE id = $1 AND status = 'onizleme' RETURNING id", [id]);
    if (!claim.rows[0]) { await client.query("ROLLBACK"); return { already: true, import: await getImport(user, id) }; }
    const cv = await client.query(
      `INSERT INTO conversations (org_id, owner_user_id, source, convo_key, customer_id, phone_key, offer_id, project_id, title, is_group, participants, owner_sender, retention_until)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
       ON CONFLICT ((COALESCE(owner_user_id, '00000000-0000-0000-0000-000000000000'::uuid)), convo_key)
       DO UPDATE SET title = EXCLUDED.title, owner_sender = EXCLUDED.owner_sender, participants = EXCLUDED.participants,
                     customer_id = COALESCE(EXCLUDED.customer_id, conversations.customer_id), offer_id = COALESCE(EXCLUDED.offer_id, conversations.offer_id),
                     project_id = COALESCE(EXCLUDED.project_id, conversations.project_id),
                     retention_until = GREATEST(conversations.retention_until, EXCLUDED.retention_until)
       RETURNING id`,
      [orgId, user.id, imp.source, convoKey, customerRowId, phoneKey, offerId, projectId, title, !!stats.is_group, JSON.stringify(participants.map((p) => ({ name: p.name, count: p.count }))), needOwner ? ownerSender : null, retentionUntil]);
    convoId = cv.rows[0].id;
    const hashes = msgs.map((m) => hashOf(m.dedupeKey, m.n));
    for (let i = 0; i < msgs.length; i += 1000) {
      const part = msgs.slice(i, i + 1000), ph = hashes.slice(i, i + 1000), pr = roles.slice(i, i + 1000);
      const r = await client.query(
        `INSERT INTO conversation_messages (org_id, conversation_id, import_id, source, role, sender, kind, content, content_hash, sent_at, raw_expires_at)
         SELECT $1,$2,$3,$4,u.r,u.s,u.k,u.c,u.h,u.t::timestamptz,$5 FROM unnest($6::text[],$7::text[],$8::text[],$9::text[],$10::text[],$11::text[]) AS u(r,s,k,c,h,t)
         ON CONFLICT (conversation_id, content_hash) DO NOTHING`,
        [orgId, convoId, id, imp.source, rawExp, pr, part.map((m) => m.sender), part.map((m) => m.kind), part.map((m) => (m.text == null ? null : m.text)), ph, part.map((m) => m.ts.toISOString())]);
      inserted += r.rowCount;
    }
    // öneriler (kaynak mesaja bağlı)
    if (b.create_suggestions !== false) {
      const ex = runExtractor(msgs, roles, title, now);
      sugTotal = ex.suggestions.length;
      if (sugTotal) {
        const idRows = await client.query("SELECT id, content_hash FROM conversation_messages WHERE conversation_id = $1 AND content_hash = ANY($2::text[])", [convoId, hashes]);
        const idByHash = new Map(idRows.rows.map((r) => [r.content_hash, r.id]));
        for (const s of ex.suggestions) {
          const mid = idByHash.get(hashes[s.msgIndex]);
          if (!mid) continue;
          const r = await client.query(
            `INSERT INTO ai_suggestions (org_id, user_id, conversation_id, import_id, source_message_id, kind, payload, origin, status, dedupe_key, confidence, expires_at)
             VALUES ($1,$2,$3,$4,$5,$6,$7,'rule','beklemede',$8,$9,$10) ON CONFLICT (conversation_id, dedupe_key) DO NOTHING`,
            [orgId, user.id, convoId, id, mid, s.kind, JSON.stringify(s.payload), s.dedupeKey, s.confidence, new Date(now.getTime() + SUGGESTION_TTL_MS)]);
          sugInserted += r.rowCount;
        }
      }
    }
    await client.query(
      `UPDATE conversations c SET message_count = x.n, first_message_at = x.a, last_message_at = x.b
         FROM (SELECT COUNT(*)::int n, MIN(sent_at) a, MAX(sent_at) b FROM conversation_messages WHERE conversation_id = $1) x WHERE c.id = $1`, [convoId]);
    await client.query(`UPDATE conversation_imports SET staged = NULL, candidates = '[]'::jsonb, conversation_id = $2, inserted_count = $3, duplicate_count = $4 WHERE id = $1`, [id, convoId, inserted, msgs.length - inserted]);
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
  await logAction({ req, orgId, action: "assistant.import.confirm", entityType: "conversation_import", entityId: id, data: { conversation_id: convoId, inserted, duplicates: msgs.length - inserted, suggestions: sugInserted } });
  return { already: false, import: await getImport(user, id), conversation_id: convoId, inserted, duplicates: msgs.length - inserted, suggestions_created: sugInserted };
}

// ---------- okuma / silme ----------
function serializeImport(r) {
  return { id: r.id, status: r.status, source: r.source, file: { label: r.file_label, kind: r.file_kind, bytes: r.file_bytes }, stats: r.stats, candidates: r.status === "onizleme" ? r.candidates : [], conversation_id: r.conversation_id, inserted_count: r.inserted_count, duplicate_count: r.duplicate_count, expires_at: r.expires_at, created_at: r.created_at, confirmed_at: r.confirmed_at };
}
async function getImport(user, id) { return serializeImport(await loadOwnImport(user, id)); }
async function listImports(user, limit) {
  const lim = Math.min(Math.max(parseInt(limit, 10) || 30, 1), 100);
  const { rows } = await db.query(`SELECT * FROM conversation_imports WHERE ${user.role === "admin" ? "TRUE" : "user_id = $2"} ORDER BY created_at DESC LIMIT $1`, user.role === "admin" ? [lim] : [lim, user.id]);
  return rows.map(serializeImport);
}

/** İçe aktarmayı sil: önizleme → iptal/silme; onaylı → mesajlar, öneriler ve (keepNotes yoksa) notlar silinir */
async function deleteImport(req, id, { keepNotes }) {
  const user = req.user;
  const imp = await loadOwnImport(user, id);
  const client = await db.pool.connect();
  let removed = { messages: 0, suggestions: 0, notes: 0 };
  try {
    await client.query("BEGIN");
    if (keepNotes) await client.query("UPDATE ai_notes SET import_id = NULL, conversation_id = NULL, source_message_id = NULL WHERE import_id = $1 AND status = 'active'", [id]);
    removed.messages = (await client.query("SELECT COUNT(*)::int n FROM conversation_messages WHERE import_id = $1", [id])).rows[0].n;
    removed.suggestions = (await client.query("SELECT COUNT(*)::int n FROM ai_suggestions WHERE import_id = $1", [id])).rows[0].n;
    removed.notes = (await client.query("SELECT COUNT(*)::int n FROM ai_notes WHERE import_id = $1", [id])).rows[0].n;
    await client.query("DELETE FROM conversation_imports WHERE id = $1", [id]);
    if (imp.conversation_id) {
      const left = await client.query("SELECT COUNT(*)::int n FROM conversation_messages WHERE conversation_id = $1", [imp.conversation_id]);
      if (left.rows[0].n === 0) await client.query("DELETE FROM conversations WHERE id = $1", [imp.conversation_id]);
      else await client.query(`UPDATE conversations c SET message_count = x.n, first_message_at = x.a, last_message_at = x.b FROM (SELECT COUNT(*)::int n, MIN(sent_at) a, MAX(sent_at) b FROM conversation_messages WHERE conversation_id = $1) x WHERE c.id = $1`, [imp.conversation_id]);
    }
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
  await logAction({ req, action: "assistant.import.delete", entityType: "conversation_import", entityId: id, data: { ...removed, keep_notes: !!keepNotes, status: imp.status } });
  return { deleted: true, removed };
}

module.exports = { ImportError, createPreview, confirmImport, getImport, listImports, deleteImport, readUpload, decodeText, safeLabel, matchCandidates, guessOwner, MAX_MESSAGES, MAX_TEXT_BYTES };
