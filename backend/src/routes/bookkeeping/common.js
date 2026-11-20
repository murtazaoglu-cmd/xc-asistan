/**
 * v18 ortak yardımcılar: roller, defter sahibi, doğrulama, referans verisi (KDV oranları/tatiller) yükleme, teyit bayrakları.
 * Rol modeli: admin/muhasebe tam (işletme defteri = ilk admin), ortak yalnız KENDİ defteri; personel/saha → 403 (requireRole).
 */
const db = require("../../db");
const { requireAuth, requireRole } = require("../../middleware/auth");
const { financeOwnerId } = require("../../middleware/access");
const { canAccessResource } = require("../../middleware/ownership");
const { isValidIsoDate, todayIstanbul } = require("../../assistant/tax/dates");
const { parsePeriodKey } = require("../../assistant/tax/vatPeriod");
const { orgIdForUser } = require("../../assistant/org");

const guard = [requireAuth, requireRole("admin", "muhasebe", "ortak")];
const staffOnly = [requireAuth, requireRole("admin", "muhasebe")];
const isStaff = (u) => u.role === "admin" || u.role === "muhasebe";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (v) => typeof v === "string" && UUID_RE.test(v);

function httpError(status, message, extra) {
  const e = new Error(message); e.status = status; e.expose = true; if (extra) Object.assign(e, { extra });
  return e;
}
/** Route'larda: hata nesnelerini {error, ...extra} olarak döndür (server.js genel işleyicisi yalnız message yazar) */
function sendError(res, err) {
  if (err && err.status && err.status < 500) return res.status(err.status).json({ error: err.message, ...(err.extra || {}) });
  throw err;
}

/** async handler sarmalayıcı: httpError → {error, ...extra}; diğer hatalar genel işleyiciye (500) gider */
const wrap = (fn) => async (req, res, next) => {
  try { await fn(req, res, next); } catch (e) {
    if (e && e.status && e.status < 500 && e.expose !== false) return res.status(e.status).json({ error: e.message, ...(e.extra || {}) });
    next(e);
  }
};

const ledgerOf = (req) => financeOwnerId(req.user);
/** İsteği yapan kullanıcının kuruluşu (oranlar/takvim/tatil/vergi ayarı kuruluş verisidir) */
const orgOf = (req) => orgIdForUser(req.user.id);
const today = () => todayIstanbul();

/** İsteğe bağlı metin alanı: null/"" → null; string değilse ya da max aşılırsa hata fırlatır */
function optText(v, name, max) {
  if (v === undefined) return undefined;
  if (v === null || v === "") return null;
  if (typeof v !== "string") throw httpError(400, `${name} metin olmalıdır.`);
  const s = v.trim();
  if (s.length > max) throw httpError(400, `${name} en çok ${max} karakter olabilir.`);
  return s || null;
}
function optDate(v, name) {
  if (v === undefined) return undefined;
  if (v === null || v === "") return null;
  if (!isValidIsoDate(v)) throw httpError(400, `${name} geçerli bir tarih (YYYY-AA-GG) olmalıdır.`);
  return v;
}
function optUuid(v, name) {
  if (v === undefined) return undefined;
  if (v === null || v === "") return null;
  if (!isUuid(v)) throw httpError(400, `${name} geçersiz.`);
  return v;
}
function optBool(v, name) {
  if (v === undefined) return undefined;
  if (typeof v !== "boolean") throw httpError(400, `${name} true/false olmalıdır.`);
  return v;
}
function oneOf(v, list, name) {
  if (!list.includes(v)) throw httpError(400, `${name} şunlardan biri olmalıdır: ${list.join(", ")}.`);
  return v;
}

/** period=YYYY | YYYY-MM | YYYY-Qn → {from, to} (iki uç dahil) */
function periodRange(period) {
  if (typeof period !== "string") return null;
  if (/^\d{4}$/.test(period)) return { from: `${period}-01-01`, to: `${period}-12-31`, label: period };
  const p = parsePeriodKey(period);
  return p ? { from: p.startsOn, to: p.endsOn, label: period } : null;
}

/** Bağlı kayıtların varlığı ve erişimi (project/offer: mevcut sahiplik kuralları; customer/payment/expense: defter) */
async function checkLink(req, kind, id, ledgerId) {
  if (!id) return;
  if (kind === "project" || kind === "offer") {
    const table = kind === "project" ? "projects" : "offers";
    const { rows } = await db.query(`SELECT owner_id FROM ${table} WHERE id = $1`, [id]);
    if (!rows[0]) throw httpError(404, kind === "project" ? "Proje bulunamadı." : "Teklif bulunamadı.");
    if (!(await canAccessResource(req.user, kind, id, rows[0].owner_id))) throw httpError(403, kind === "project" ? "Bu projeye erişiminiz yok." : "Bu teklife erişiminiz yok.");
  } else if (kind === "customer") {
    const { rows } = await db.query("SELECT owner_id FROM customers WHERE id = $1", [id]);
    if (!rows[0]) throw httpError(404, "Müşteri bulunamadı.");
    if (!isStaff(req.user) && String(rows[0].owner_id) !== String(req.user.id)) throw httpError(403, "Bu müşteriye erişiminiz yok.");
  } else if (kind === "payment" || kind === "expense") {
    const table = kind === "payment" ? "payments" : "expenses";
    const { rows } = await db.query(`SELECT owner_id FROM ${table} WHERE id = $1`, [id]);
    if (!rows[0]) throw httpError(404, kind === "payment" ? "Ödeme bulunamadı." : "Gider bulunamadı.");
    if (String(rows[0].owner_id) !== String(ledgerId)) throw httpError(403, kind === "payment" ? "Bu ödeme defterinize ait değil." : "Bu gider defterinize ait değil.");
  } else if (kind === "invoice") {
    const { rows } = await db.query("SELECT owner_id FROM invoices WHERE id = $1", [id]);
    if (!rows[0]) throw httpError(404, "Fatura bulunamadı.");
    if (String(rows[0].owner_id) !== String(ledgerId)) throw httpError(404, "Fatura bulunamadı.");
  }
}

// ------------------------------------------------------------------ referans verisi
async function loadRates(orgId) {
  const [r, w] = await Promise.all([
    db.query("SELECT * FROM (SELECT id, org_id, code, rate, label, is_default, enabled, verified, note, source, verified_by, verified_at, created_at, updated_at, valid_from::text AS valid_from, valid_to::text AS valid_to FROM vat_rates) v WHERE org_id = $1 ORDER BY rate DESC, valid_from NULLS FIRST", [orgId]),
    db.query("SELECT * FROM vat_withholding_types WHERE org_id = $1 ORDER BY pay, payda", [orgId]),
  ]);
  return { rates: r.rows, withholding: w.rows };
}
async function loadHolidays(orgId, from, to) {
  const { rows } = await db.query("SELECT day::text AS day, name, kind, half_day, verified FROM holidays_tr WHERE org_id = $1 AND day BETWEEN $2 AND $3 ORDER BY day", [orgId, from, to]);
  return rows;
}
async function loadCalendarItems(orgId) {
  const { rows } = await db.query("SELECT *, due_date::text AS due_date FROM tax_calendar_items WHERE org_id = $1 ORDER BY key", [orgId]);
  return rows;
}
async function loadTaxSettings(orgId) {
  const { rows } = await db.query("SELECT org_id, tax_status, vat_period_type, note, updated_at FROM org_tax_settings WHERE org_id = $1", [orgId]);
  return rows[0] || { org_id: orgId, tax_status: null, vat_period_type: "aylik", note: null, updated_at: null };
}

/** Faturanın oranı için geçerli vat_rates kaydı (etkin + fatura tarihinde geçerli) */
function findRate(rates, rate, issueDate) {
  return rates.find((r) => r.enabled && Number(r.rate) === Number(rate) && (!r.valid_from || String(r.valid_from).slice(0, 10) <= issueDate) && (!r.valid_to || String(r.valid_to).slice(0, 10) >= issueDate)) || null;
}
const defaultRate = (rates) => rates.find((r) => r.enabled && r.is_default) || null;

/**
 * "Mali müşavire teyit" bayrağı: oran/tevkifat doğrulanmamış ya da listede yoksa, istisna nedeni yazılmamışsa vb.
 * @returns {{needed:boolean, reasons:string[]}}
 */
function invoiceConfirmation(inv, ref) {
  const reasons = [];
  const d = String(inv.issue_date).slice(0, 10);
  const r = findRate(ref.rates, inv.kdv_oran, d);
  if (!r) reasons.push(`KDV oranı (%${Number(inv.kdv_oran)}) oran listesinde (vat_rates) yok — mali müşavire teyit`);
  else if (!r.verified) reasons.push(`KDV oranı (%${Number(inv.kdv_oran)}) doğrulanmadı — mali müşavire teyit`);
  if (Number(inv.kdv_oran) === 0 && !inv.kdv_istisna_nedeni) reasons.push("KDV %0 için istisna nedeni yazılmamış");
  if (inv.tevkifat_pay) {
    const t = ref.withholding.find((x) => x.enabled && x.pay === inv.tevkifat_pay && x.payda === inv.tevkifat_payda);
    if (!t) reasons.push(`Tevkifat oranı (${inv.tevkifat_pay}/${inv.tevkifat_payda}) listede yok — mali müşavire teyit`);
    else if (!t.verified) reasons.push(`Tevkifat oranı (${inv.tevkifat_pay}/${inv.tevkifat_payda}) doğrulanmadı — mali müşavire teyit`);
  }
  return { needed: reasons.length > 0, reasons };
}

module.exports = {
  db, guard, staffOnly, isStaff, isUuid, httpError, sendError, wrap, ledgerOf, orgOf, loadTaxSettings, today, optText, optDate, optUuid, optBool, oneOf,
  periodRange, checkLink, loadRates, loadHolidays, loadCalendarItems, findRate, defaultRate, invoiceConfirmation,
};
