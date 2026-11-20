/**
 * /api/message-templates — WhatsApp mesaj şablonları (sıfır maliyet: wa.me derin bağlantısı; uygulama GÖNDERMEZ, kullanıcı kendi WhatsApp'ından gönderir).
 * Sistem şablonları (owner_id NULL) salt okunurdur; "özelleştirme" = aynı anahtarla kendi defterinize kopya (clone / POST). Liste, aynı anahtarda kendi sürümünüzü gösterir.
 * Roller: admin/muhasebe/ortak. Render erişimi ilgili kaydın (müşteri/teklif/proje/randevu/plan/fatura) mevcut erişim kurallarına tabidir.
 */
const express = require("express");
const C = require("./common");
const { db } = C;
const MT = require("../../assistant/tax/messageTemplates");
const { toKurus } = require("../../assistant/tax/money");
const { canAccessResource } = require("../../middleware/ownership");
const { orgIdForUser } = require("../../assistant/org");

const router = express.Router();
const CATEGORIES = ["teklif", "randevu", "odeme", "tesekkur", "diger"];
const TONES = ["nazik", "orta", "kesin"];
const COLS = "id, owner_id, key, title, category, tone, sector, body, legal_note, is_system, enabled, sort_order, created_at, updated_at";

/** Gövde doğrulaması: uzunluk, dengeli [[ ]], yalnız bilinen değişkenler */
function checkBody(body) {
  if (typeof body !== "string" || !body.trim()) throw C.httpError(400, "body zorunludur.");
  if (body.length > 2000) throw C.httpError(400, "body en çok 2000 karakter olabilir.");
  const open = (body.match(/\[\[/g) || []).length, close = (body.match(/\]\]/g) || []).length;
  if (open !== close) throw C.httpError(400, "İsteğe bağlı bloklar [[ … ]] dengeli olmalıdır.");
  const unknown = MT.extractVars(body).filter((v) => !(v in MT.VARIABLES));
  if (unknown.length) throw C.httpError(400, `Bilinmeyen değişken(ler): ${unknown.map((u) => "{" + u + "}").join(", ")}. GET /api/message-templates/variables ile listeyi görün.`, { unknown });
  return body;
}
const view = (r) => ({ ...r, variables: MT.extractVars(r.body), editable: !r.is_system });

async function loadVisible(id, ledger) {
  if (!C.isUuid(id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const { rows } = await db.query(`SELECT ${COLS} FROM message_templates WHERE id = $1`, [id]);
  const r = rows[0];
  if (!r || (r.owner_id && String(r.owner_id) !== String(ledger))) throw C.httpError(404, "Şablon bulunamadı.");
  return r;
}

router.get("/variables", C.guard, (req, res) => res.json(MT.VARIABLES));

/** Liste: varsayılan olarak her (anahtar, sektör) için ETKİN sürüm (kendi özelleştirmeniz sistem şablonunu ezer). ?all=1 → hepsi */
router.get("/", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req); const q = req.query;
  const params = [ledger]; let where = "(owner_id IS NULL OR owner_id = $1)";
  if (q.category !== undefined) { params.push(C.oneOf(q.category, CATEGORIES, "category")); where += ` AND category = $${params.length}`; }
  if (q.tone !== undefined) { params.push(C.oneOf(q.tone, TONES, "tone")); where += ` AND tone = $${params.length}`; }
  if (q.sector !== undefined) { params.push(q.sector); where += ` AND (sector = $${params.length} OR sector IS NULL)`; }
  if (q.enabled !== "all") where += " AND enabled";
  const { rows } = await db.query(`SELECT ${COLS} FROM message_templates WHERE ${where} ORDER BY sort_order, key`, params);
  let out = rows;
  if (q.all !== "1" && q.all !== "true") {
    const best = new Map();
    for (const r of rows) { // aynı anahtar: kendi sürüm > sektör eşleşen > genel sistem
      const score = (r.owner_id ? 2 : 0) + (r.sector && r.sector === q.sector ? 1 : 0);
      const cur = best.get(r.key);
      if (!cur || score > cur.score) best.set(r.key, { score, r });
    }
    out = [...best.values()].map((x) => x.r).sort((a, b) => a.sort_order - b.sort_order || (a.key < b.key ? -1 : 1));
  }
  res.json(out.map(view));
}));

router.get("/:id", C.guard, C.wrap(async (req, res) => res.json(view(await loadVisible(req.params.id, await C.ledgerOf(req))))));

function fields(b, create) {
  const out = {};
  const key = C.optText(b.key, "key", 60); if (create && !key) throw C.httpError(400, "key zorunludur."); if (key) { if (!/^[a-z0-9_]{2,60}$/.test(key)) throw C.httpError(400, "key küçük harf/rakam/alt çizgi olmalıdır."); out.key = key; }
  const title = C.optText(b.title, "title", 120); if (create && !title) throw C.httpError(400, "title zorunludur."); if (title) out.title = title;
  if (b.category !== undefined) out.category = C.oneOf(b.category, CATEGORIES, "category"); else if (create) out.category = "diger";
  if (b.tone !== undefined) out.tone = b.tone === null ? null : C.oneOf(b.tone, TONES, "tone");
  const sector = C.optText(b.sector, "sector", 60); if (sector !== undefined) out.sector = sector;
  if (create || b.body !== undefined) out.body = checkBody(b.body);
  const en = C.optBool(b.enabled, "enabled"); if (en !== undefined) out.enabled = en;
  if (b.sort_order !== undefined) { if (!Number.isInteger(b.sort_order) || b.sort_order < 0 || b.sort_order > 10000) throw C.httpError(400, "sort_order 0-10000 arasında tamsayı olmalıdır."); out.sort_order = b.sort_order; }
  const ln = C.optText(b.legal_note, "legal_note", 500); if (ln !== undefined) out.legal_note = ln;
  return out;
}

router.post("/", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req);
  const f = fields(req.body || {}, true);
  const cols = Object.keys(f);
  try {
    const { rows } = await db.query(`INSERT INTO message_templates (owner_id, org_id, is_system, ${cols.join(",")}) VALUES ($1, $2, false, ${cols.map((_, i) => "$" + (i + 3)).join(",")}) RETURNING ${COLS}`, [ledger, await orgIdForUser(ledger), ...cols.map((c) => f[c])]);
    res.status(201).json(view(rows[0]));
  } catch (e) { if (e.code === "23505") throw C.httpError(409, "Bu anahtar (ve sektör) için kendi şablonunuz zaten var; düzenleyin."); throw e; }
}));

/** Sistem (ya da başka) şablonu kendi defterinize kopyala → düzenlenebilir özelleştirme */
router.post("/:id/clone", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req);
  const src = await loadVisible(req.params.id, ledger);
  try {
    const { rows } = await db.query(
      `INSERT INTO message_templates (owner_id, org_id, key, title, category, tone, sector, body, legal_note, is_system, sort_order) VALUES ($1,$10,$2,$3,$4,$5,$6,$7,$8,false,$9) RETURNING ${COLS}`,
      [ledger, src.key, src.title, src.category, src.tone, src.sector, src.body, src.legal_note, src.sort_order, await orgIdForUser(ledger)]);
    res.status(201).json(view(rows[0]));
  } catch (e) { if (e.code === "23505") throw C.httpError(409, "Bu anahtar (ve sektör) için kendi şablonunuz zaten var."); throw e; }
}));

router.patch("/:id", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req);
  const row = await loadVisible(req.params.id, ledger);
  if (row.is_system || !row.owner_id) throw C.httpError(403, "Sistem şablonu düzenlenemez; POST /api/message-templates/:id/clone ile kendi sürümünüzü oluşturun.");
  const f = fields(req.body || {}, false);
  const cols = Object.keys(f); if (!cols.length) throw C.httpError(400, "Güncellenecek alan yok.");
  try {
    const { rows } = await db.query(`UPDATE message_templates SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(", ")}, updated_at = now() WHERE id = $${cols.length + 1} RETURNING ${COLS}`, [...cols.map((c) => f[c]), row.id]);
    res.json(view(rows[0]));
  } catch (e) { if (e.code === "23505") throw C.httpError(409, "Bu anahtar (ve sektör) için başka bir şablonunuz var."); throw e; }
}));

router.delete("/:id", C.guard, C.wrap(async (req, res) => {
  const row = await loadVisible(req.params.id, await C.ledgerOf(req));
  if (row.is_system || !row.owner_id) throw C.httpError(403, "Sistem şablonu silinemez (pasifleştirmek için kendi sürümünüzü enabled:false yapın).");
  await db.query("DELETE FROM message_templates WHERE id = $1", [row.id]);
  res.json({ message: "Silindi." });
}));

// ------------------------------------------------------------------ render
async function buildContext(req, b, ledger) {
  const ctx = { siteUrl: process.env.SITE_URL, override: {} };
  const notes = {}; // yanıtta hangi kayıtlarla dolduruldu
  const bad = (k) => { throw C.httpError(400, `${k} geçersiz.`); };
  const id = (k) => { const v = C.optUuid(b[k], k); return v || null; };

  let schedule = null, invoice = null;
  const scheduleId = id("schedule_id"), invoiceId = id("invoice_id");
  let projectId = id("project_id"), offerId = id("offer_id");
  const customerId = id("customer_id"), appointmentId = id("appointment_id");

  if (scheduleId) {
    const { rows } = await db.query("SELECT owner_id, project_id, offer_id, invoice_id, amount_kurus, due_date::text AS due_date, status FROM payment_schedule WHERE id = $1", [scheduleId]);
    if (!rows[0]) throw C.httpError(404, "Plan satırı bulunamadı.");
    if (String(rows[0].owner_id) !== String(ledger)) throw C.httpError(404, "Plan satırı bulunamadı.");
    schedule = rows[0]; projectId = projectId || schedule.project_id; offerId = offerId || schedule.offer_id;
    notes.schedule_id = scheduleId;
  }
  if (invoiceId || (schedule && schedule.invoice_id)) {
    const iid = invoiceId || schedule.invoice_id;
    const { rows } = await db.query("SELECT owner_id, invoice_no, odenecek_kurus, due_date::text AS due_date, counterparty, project_id, offer_id, customer_id FROM invoices WHERE id = $1", [iid]);
    if (!rows[0]) throw C.httpError(404, "Fatura bulunamadı.");
    if (String(rows[0].owner_id) !== String(ledger)) throw C.httpError(404, "Fatura bulunamadı.");
    invoice = rows[0]; projectId = projectId || invoice.project_id; offerId = offerId || invoice.offer_id; notes.invoice_id = iid;
  }
  if (customerId) {
    await C.checkLink(req, "customer", customerId, ledger);
    ctx.customer = (await db.query("SELECT name, phone, address FROM customers WHERE id = $1", [customerId])).rows[0];
    notes.customer_id = customerId;
  } else if (invoice && invoice.customer_id) {
    ctx.customer = (await db.query("SELECT name, phone, address FROM customers WHERE id = $1", [invoice.customer_id])).rows[0];
  }
  if (projectId) {
    await C.checkLink(req, "project", projectId, ledger);
    const p = (await db.query("SELECT code, customer_name, service, total_amount, offer_id, address FROM projects WHERE id = $1", [projectId])).rows[0];
    ctx.project = p; offerId = offerId || p.offer_id; notes.project_id = projectId;
    const paid = (await db.query("SELECT COALESCE(SUM(amount),0) AS s FROM payments WHERE project_id = $1 AND owner_id = $2", [projectId, ledger])).rows[0].s;
    const extras = (await db.query("SELECT COALESCE(SUM(amount),0) AS s FROM project_extras WHERE project_id = $1", [projectId])).rows[0].s;
    const total = toKurus(Number(p.total_amount) + Number(extras)), paidK = toKurus(Number(paid));
    if (total !== null && paidK !== null && total > 0) ctx.remainingKurus = Math.max(total - paidK, 0);
  }
  if (offerId) {
    await C.checkLink(req, "offer", offerId, ledger);
    ctx.offer = (await db.query("SELECT code, name, phone, service, tracking_code, address FROM offers WHERE id = $1", [offerId])).rows[0];
    const q = (await db.query("SELECT total FROM quotes WHERE offer_id = $1 ORDER BY created_at DESC LIMIT 1", [offerId])).rows[0];
    if (q) ctx.quoteTotalKurus = toKurus(Number(q.total));
    notes.offer_id = offerId;
  }
  if (appointmentId) {
    const a = (await db.query("SELECT owner_id, assigned_user_id, offer_id, project_id, type, scheduled_at, address, customer_name, customer_phone FROM appointments WHERE id = $1", [appointmentId])).rows[0];
    if (!a) throw C.httpError(404, "Randevu bulunamadı.");
    if (!C.isStaff(req.user) && String(a.owner_id) !== String(req.user.id) && String(a.assigned_user_id) !== String(req.user.id)) throw C.httpError(403, "Bu randevuya erişiminiz yok.");
    ctx.appointment = a; notes.appointment_id = appointmentId;
  }
  if (schedule) ctx.schedule = { amount_kurus: Number(schedule.amount_kurus), due_date: schedule.due_date };
  if (invoice) {
    ctx.invoice = { invoice_no: invoice.invoice_no, odenecek_kurus: Number(invoice.odenecek_kurus), due_date: invoice.due_date };
    if (!ctx.customer && !ctx.offer && !ctx.project && invoice.counterparty) ctx.customer = { name: invoice.counterparty, phone: null };
  }
  return { ctx, notes };
}

/** POST /api/message-templates/:id/render  {customer_id|offer_id|project_id|schedule_id|invoice_id|appointment_id, vars?, phone?, opt_out?} → {text, whatsappUrl, …} */
router.post("/:id/render", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req); const b = req.body || {};
  const tpl = await loadVisible(req.params.id, ledger);
  if (b.vars !== undefined && (typeof b.vars !== "object" || b.vars === null || Array.isArray(b.vars))) throw C.httpError(400, "vars bir nesne olmalıdır.");
  for (const [k, v] of Object.entries(b.vars || {})) {
    if (!(k in MT.VARIABLES)) throw C.httpError(400, `Bilinmeyen değişken: ${k}.`);
    if (typeof v !== "string" && typeof v !== "number") throw C.httpError(400, `vars.${k} metin ya da sayı olmalıdır.`);
  }
  const { ctx, notes } = await buildContext(req, b, ledger);
  const orgRow = (await db.query("SELECT COALESCE(NULLIF(s.brand->>'name',''), o.name) AS name FROM organizations o LEFT JOIN org_settings s ON s.org_id = o.id WHERE o.id = $1", [await orgIdForUser(ledger)])).rows[0];
  Object.assign(ctx, {
    firma_adi: process.env.COMPANY_NAME || (orgRow && orgRow.name) || null, telefon: process.env.COMPANY_PHONE || null, iban_unvan: process.env.COMPANY_IBAN_INFO || null,
    override: b.vars || {}, optOut: b.opt_out === true, phoneOverride: b.phone === undefined || b.phone === null || b.phone === "" ? null : String(b.phone),
  });
  const { vars, phone } = MT.buildVars(ctx);
  if (!vars.kalan_tutar && vars.tutar && (ctx.schedule || ctx.invoice)) vars.kalan_tutar = vars.tutar; // plan/fatura bağlamında kalan = o kalemin tutarı
  const out = MT.renderTemplate(tpl.body, vars);
  const links = MT.buildWhatsAppLinks(phone, out.text);
  const warnings = [];
  if (!links.phone) warnings.push({ code: "phone_missing_or_invalid", message: phone ? "Telefon numarası geçersiz; wa.me bağlantısı üretilemedi." : "Müşteri telefonu bulunamadı (phone gönderin); wa.me bağlantısı üretilemedi." });
  if (links.urlTooLong) warnings.push({ code: "url_too_long", message: "Bağlantı ~2000 karakteri aşıyor; bazı cihazlarda metin kesilebilir. Şablonu kısaltın." });
  if (!out.complete) warnings.push({ code: "missing_variables", message: `Doldurulamayan değişkenler: ${out.missing.map((m) => "{" + m + "}").join(", ")}` });
  if (tpl.category === "odeme") warnings.push({ code: "payment_reminder_rules", message: "Ödeme hatırlatmasına tanıtım/kampanya eklemeyin; tehdit/icra dili, günde birden çok mesaj ve gece saatlerinden kaçının (avukata teyit edin)." });
  res.json({
    text: out.text, whatsappUrl: links.whatsappUrl, whatsappAppUrl: links.whatsappAppUrl, phone: links.phone,
    missing: out.missing, complete: out.complete, urlTooLong: links.urlTooLong,
    template: { id: tpl.id, key: tpl.key, title: tpl.title, category: tpl.category, tone: tpl.tone }, context: notes, variables: vars, warnings,
  });
}));

module.exports = router;
