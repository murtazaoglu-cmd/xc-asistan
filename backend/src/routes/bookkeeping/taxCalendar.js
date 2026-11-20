/**
 * /api/tax-calendar — vergi takvimi (yaklaşanlar) + takvim kalemleri + resmî tatiller. Okuma: admin/muhasebe/ortak; DÜZENLEME: yalnız admin/muhasebe.
 * Tarihler VERİDİR ve TAHMİNİDİR; her oluşum `needs_confirmation` (mali müşavire teyit) taşır. Takvim ortak (firma geneli) veridir; defterden bağımsızdır.
 */
const express = require("express");
const C = require("./common");
const { db } = C;
const TC = require("../../assistant/tax/taxCalendar");
const { addDays, isValidIsoDate } = require("../../assistant/tax/dates");
const planner = require("../../assistant/tax/reminderPlanner");

const router = express.Router();
const KINDS = ["kdv", "kdv2", "muhtasar", "gecici_vergi", "yillik_beyan", "ba_bs", "e_defter", "sgk", "bilgi", "diger"];
const APPLIES = ["hepsi", "sahis", "limited"];
const CONF = ["birincil", "ikincil", "belirsiz"];
const DISCLAIMER = "Tarihler tahminidir ve hukuki kaynak değildir (hafta sonu/resmî tatil kaydırması dahil). Resmî takvimle/mali müşavirle teyit edin.";

router.get("/", C.guard, C.wrap(async (req, res) => {
  const today = C.optDate(req.query.asOf, "asOf") || C.today();
  const days = req.query.days === undefined ? 45 : Number(req.query.days);
  if (!Number.isInteger(days) || days < 1 || days > 400) throw C.httpError(400, "days 1-400 arasında olmalıdır.");
  const from = C.optDate(req.query.from, "from") || today;
  const to = C.optDate(req.query.to, "to") || addDays(from, days);
  if (to < from) throw C.httpError(400, "to, from'dan önce olamaz.");
  const statu = req.query.statu === undefined ? undefined : C.oneOf(req.query.statu, ["sahis", "limited"], "statu");
  const orgId = await C.orgOf(req);
  const settings = await C.loadTaxSettings(orgId);
  const eff = statu || settings.tax_status || undefined; // açık ?statu → ayar → belirtilmedi (yalnız 'hepsi' kalemleri)
  const [items, holidays] = await Promise.all([C.loadCalendarItems(orgId), C.loadHolidays(orgId, addDays(from, -45), addDays(to, 45))]);
  planner.bootstrap(); // zamanlı hatırlatma zincirini (idempotent) başlat
  const occ = TC.occurrences(items, { from, to, holidays, today, appliesTo: eff });
  res.json({ asOf: today, from, to, statu: eff || null, statu_source: statu ? "query" : settings.tax_status ? "settings" : null, items: occ, needs_confirmation_count: occ.filter((o) => o.needs_confirmation).length, disclaimer: DISCLAIMER });
}));

// ------------------------------------------------------------ vergi ayarı (statü / KDV dönemi)
const STATUS_TR_SET = ["sahis", "limited"];
router.get("/settings", C.guard, C.wrap(async (req, res) => {
  const st = await C.loadTaxSettings(await C.orgOf(req));
  res.json({ tax_status: st.tax_status, vat_period_type: st.vat_period_type, note: st.note, updated_at: st.updated_at,
    note_tr: "tax_status belirtilmezse hatırlatmalar yalnız herkesi ilgilendiren takvim kalemlerini kapsar. Statünüzü mali müşavirinize sorun." });
}));
router.put("/settings", C.staffOnly, C.wrap(async (req, res) => {
  const b = req.body || {}; const orgId = await C.orgOf(req);
  const cur = await C.loadTaxSettings(orgId);
  const next = { tax_status: cur.tax_status, vat_period_type: cur.vat_period_type, note: cur.note };
  let touched = false;
  if (b.tax_status !== undefined) { next.tax_status = b.tax_status === null ? null : C.oneOf(b.tax_status, STATUS_TR_SET, "tax_status"); touched = true; }
  if (b.vat_period_type !== undefined) { next.vat_period_type = C.oneOf(b.vat_period_type, ["aylik", "uc_aylik"], "vat_period_type"); touched = true; }
  if (b.note !== undefined) { next.note = C.optText(b.note, "note", 2000); touched = true; }
  if (!touched) throw C.httpError(400, "Güncellenecek alan yok (tax_status, vat_period_type, note).");
  await db.query(
    `INSERT INTO org_tax_settings (org_id, tax_status, vat_period_type, note, updated_by) VALUES ($1,$2,$3,$4,$5)
     ON CONFLICT (org_id) DO UPDATE SET tax_status = EXCLUDED.tax_status, vat_period_type = EXCLUDED.vat_period_type, note = EXCLUDED.note, updated_by = EXCLUDED.updated_by, updated_at = now()`,
    [orgId, next.tax_status, next.vat_period_type, next.note, req.user.id]);
  planner.bootstrap({ force: true });
  const st = await C.loadTaxSettings(orgId);
  res.json({ tax_status: st.tax_status, vat_period_type: st.vat_period_type, note: st.note, updated_at: st.updated_at });
}));

// ------------------------------------------------------------ kalemler
const withFlag = (r) => ({ ...r, needs_confirmation: !r.verified });

function itemFields(b, create) {
  const out = {};
  const key = C.optText(b.key, "key", 60);
  if (create && !key) throw C.httpError(400, "key zorunludur."); if (key) { if (!/^[a-z0-9_]{2,60}$/.test(key)) throw C.httpError(400, "key küçük harf/rakam/alt çizgi olmalıdır."); out.key = key; }
  const title = C.optText(b.title, "title", 200); if (create && !title) throw C.httpError(400, "title zorunludur."); if (title !== undefined && title !== null) out.title = title;
  if (b.kind !== undefined) out.kind = b.kind === null ? null : C.oneOf(b.kind, KINDS, "kind");
  if (b.applies_to !== undefined) out.applies_to = C.oneOf(b.applies_to, APPLIES, "applies_to");
  if (b.confidence !== undefined) out.confidence = C.oneOf(b.confidence, CONF, "confidence");
  if (b.rule !== undefined) { const e = TC.validateRule(b.rule); if (e) throw C.httpError(400, e); out.rule = b.rule === null ? null : JSON.stringify(b.rule); }
  const d = C.optDate(b.due_date, "due_date"); if (d !== undefined) out.due_date = d;
  if (create && b.rule == null && !b.due_date) throw C.httpError(400, "rule (tekrar kuralı) ya da due_date (tek seferlik tarih) gerekir.");
  for (const k of ["enabled", "verified"]) { const v = C.optBool(b[k], k); if (v !== undefined) out[k] = v; }
  for (const k of ["period_label", "source", "note"]) { const v = C.optText(b[k], k, 1000); if (v !== undefined) out[k] = v; }
  return out;
}
const ITEM_COLS = "id, key, title, kind, rule, due_date::text AS due_date, period_label, applies_to, enabled, verified, confidence, source, note, verified_by, verified_at, created_at, updated_at";

router.get("/items", C.guard, C.wrap(async (req, res) => {
  const { rows } = await db.query(`SELECT ${ITEM_COLS} FROM tax_calendar_items WHERE org_id = $1 ORDER BY kind NULLS LAST, key`, [await C.orgOf(req)]);
  res.json(rows.map(withFlag));
}));
router.post("/items", C.staffOnly, C.wrap(async (req, res) => {
  const f = itemFields(req.body || {}, true);
  f.created_by = req.user.id;
  if (f.verified === undefined) f.verified = false;
  if (f.verified) { f.verified_by = req.user.id; f.verified_at = new Date(); }
  const cols = Object.keys(f);
  let rows;
  try {
    ({ rows } = await db.query(`INSERT INTO tax_calendar_items (org_id, ${cols.join(",")}) VALUES ($${cols.length + 1}, ${cols.map((c, i) => (c === "rule" ? `$${i + 1}::jsonb` : "$" + (i + 1))).join(",")}) RETURNING ${ITEM_COLS}`, [...cols.map((c) => f[c]), await C.orgOf(req)]));
  } catch (e) { if (e.code === "23505") throw C.httpError(409, "Bu anahtarla (key) bir takvim kaydı zaten var."); throw e; }
  planner.bootstrap({ force: true });
  res.status(201).json(withFlag(rows[0]));
}));
router.patch("/items/:id", C.staffOnly, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const f = itemFields(req.body || {}, false);
  // Doğrulanmış bir kaydın tarihi/kuralı değişirse doğrulama düşer (yeniden teyit gerekir) — kullanıcı aynı istekte verified:true gönderebilir
  const changesDate = ["rule", "due_date"].some((k) => k in f);
  if (changesDate && f.verified === undefined) f.verified = false;
  if (f.verified !== undefined) { f.verified_by = f.verified ? req.user.id : null; f.verified_at = f.verified ? new Date() : null; }
  const cols = Object.keys(f);
  if (!cols.length) throw C.httpError(400, "Güncellenecek alan yok.");
  let rows;
  try {
    ({ rows } = await db.query(`UPDATE tax_calendar_items SET ${cols.map((c, i) => `${c} = $${i + 1}${c === "rule" ? "::jsonb" : ""}`).join(",")}, updated_at = now() WHERE id = $${cols.length + 1} AND org_id = $${cols.length + 2} RETURNING ${ITEM_COLS}`, [...cols.map((c) => f[c]), req.params.id, await C.orgOf(req)]));
  } catch (e) { if (e.code === "23505") throw C.httpError(409, "Bu anahtarla (key) bir takvim kaydı zaten var."); throw e; }
  if (!rows[0]) throw C.httpError(404, "Takvim kaydı bulunamadı.");
  res.json(withFlag(rows[0]));
}));
router.delete("/items/:id", C.staffOnly, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const r = await db.query("DELETE FROM tax_calendar_items WHERE id = $1 AND org_id = $2", [req.params.id, await C.orgOf(req)]);
  if (!r.rowCount) throw C.httpError(404, "Takvim kaydı bulunamadı.");
  res.json({ message: "Silindi." });
}));

// ------------------------------------------------------------ tatiller
const HOL_COLS = "day::text AS day, name, kind, half_day, verified, source, note, created_at";
function holFields(b, create) {
  const out = {};
  if (create) { if (!isValidIsoDate(b.day)) throw C.httpError(400, "day geçerli bir tarih (YYYY-AA-GG) olmalıdır."); out.day = b.day; }
  const n = C.optText(b.name, "name", 200); if (create && !n) throw C.httpError(400, "name zorunludur."); if (n) out.name = n;
  if (b.kind !== undefined) out.kind = C.oneOf(b.kind, ["resmi", "dini", "idari"], "kind");
  for (const k of ["half_day", "verified"]) { const v = C.optBool(b[k], k); if (v !== undefined) out[k] = v; }
  for (const k of ["source", "note"]) { const v = C.optText(b[k], k, 500); if (v !== undefined) out[k] = v; }
  return out;
}
router.get("/holidays", C.guard, C.wrap(async (req, res) => {
  const year = req.query.year === undefined ? +C.today().slice(0, 4) : Number(req.query.year);
  if (!Number.isInteger(year) || year < 2000 || year > 2100) throw C.httpError(400, "year geçersiz.");
  const { rows } = await db.query(`SELECT ${HOL_COLS} FROM holidays_tr WHERE org_id = $3 AND day BETWEEN $1::date AND $2::date ORDER BY day`, [`${year}-01-01`, `${year}-12-31`, await C.orgOf(req)]);
  res.json(rows.map((r) => ({ ...r, needs_confirmation: !r.verified })));
}));
router.post("/holidays", C.staffOnly, C.wrap(async (req, res) => {
  const f = holFields(req.body || {}, true); f.updated_by = req.user.id; if (f.verified === undefined) f.verified = false;
  const cols = Object.keys(f);
  let rows;
  try {
    ({ rows } = await db.query(`INSERT INTO holidays_tr (org_id, ${cols.join(",")}) VALUES ($${cols.length + 1}, ${cols.map((_, i) => "$" + (i + 1)).join(",")}) RETURNING ${HOL_COLS}`, [...cols.map((c) => f[c]), await C.orgOf(req)]));
  } catch (e) { if (e.code === "23505") throw C.httpError(409, "Bu tarih için tatil kaydı zaten var."); throw e; }
  res.status(201).json({ ...rows[0], needs_confirmation: !rows[0].verified });
}));
router.patch("/holidays/:day", C.staffOnly, C.wrap(async (req, res) => {
  if (!isValidIsoDate(req.params.day)) throw C.httpError(400, "Geçersiz tarih.");
  const f = holFields(req.body || {}, false); f.updated_by = req.user.id;
  const cols = Object.keys(f); if (cols.length < 2) throw C.httpError(400, "Güncellenecek alan yok.");
  const { rows } = await db.query(`UPDATE holidays_tr SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(",")} WHERE day = $${cols.length + 1} AND org_id = $${cols.length + 2} RETURNING ${HOL_COLS}`, [...cols.map((c) => f[c]), req.params.day, await C.orgOf(req)]);
  if (!rows[0]) throw C.httpError(404, "Tatil kaydı bulunamadı.");
  res.json({ ...rows[0], needs_confirmation: !rows[0].verified });
}));
router.delete("/holidays/:day", C.staffOnly, C.wrap(async (req, res) => {
  if (!isValidIsoDate(req.params.day)) throw C.httpError(400, "Geçersiz tarih.");
  const r = await db.query("DELETE FROM holidays_tr WHERE day = $1 AND org_id = $2", [req.params.day, await C.orgOf(req)]);
  if (!r.rowCount) throw C.httpError(404, "Tatil kaydı bulunamadı.");
  res.json({ message: "Silindi." });
}));

module.exports = router;
