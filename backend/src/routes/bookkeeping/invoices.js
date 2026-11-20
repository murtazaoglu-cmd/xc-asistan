/**
 * /api/invoices — fatura TAKİBİ (uygulama fatura kesmez). Roller: admin/muhasebe/ortak; ortak yalnız kendi defteri; personel/saha 403.
 * Para: kuruş tamsayısı (*_kurus). KDV sunucuda hesaplanır; belgedeki değerler (kdv_kurus) verilirse doğrulanır (tolerans 5 kuruş).
 */
const express = require("express");
const multer = require("multer");
const rateLimit = require("express-rate-limit");
const crypto = require("crypto");
const path = require("path");
const fs = require("fs");
const C = require("./common");
const { db } = C;
const V = require("../../assistant/tax/vat");
const VP = require("../../assistant/tax/vatPeriod");
const { fromKurus, isKurus, mulDiv } = require("../../assistant/tax/money");
const { toCsv, toXlsx } = require("../../assistant/tax/exportFile");
const { daysBetween } = require("../../assistant/tax/dates");
const { parseListParams, searchClause, queryList, sendList } = require("../../services/helpers");
const { orgIdForUser } = require("../../assistant/org");
const { UPLOAD_DIR, signRow, relFromStored, contentMatchesExt } = require("../../services/fileAccess");

const { logAction } = require("../../assistant/audit");
const audit = (req, action, id, data) => logAction({ req, action, entityType: "invoice", entityId: id, data }).catch(() => {});
const router = express.Router();

const DIRECTIONS = ["giden", "gelen"];
const TYPES = ["e-fatura", "e-arsiv", "kagit", "gider-pusulasi", "serbest-meslek", "mustahsil", "diger"];
const STATUSES = ["taslak", "kesildi", "gonderildi", "odendi", "iptal"];
const OPEN = ["kesildi", "gonderildi"];
const METHODS = ["Havale", "Nakit", "Kredi Kartı", "Çek", "Senet"];
const TYPE_TR = { "e-fatura": "e-Fatura", "e-arsiv": "e-Arşiv", kagit: "Kâğıt", "gider-pusulasi": "Gider Pusulası", "serbest-meslek": "Serbest Meslek Makbuzu", mustahsil: "Müstahsil Makbuzu", diger: "Diğer" };
const STATUS_TR = { taslak: "Taslak", kesildi: "Kesildi", gonderildi: "Gönderildi", odendi: "Ödendi", iptal: "İptal" };
const MAX_FILES = 10;
const EXPORT_MAX_ROWS = 20000;

const COLS = `i.id, i.owner_id, i.org_id, i.direction, i.invoice_type, i.invoice_no, i.ettn, i.issue_date::text AS issue_date, i.due_date::text AS due_date,
  i.counterparty, i.counterparty_tax_id, i.customer_id, i.project_id, i.offer_id, i.payment_id, i.expense_id,
  i.matrah_kurus, i.kdv_oran, i.kdv_istisna_nedeni, i.kdv_kurus, i.tevkifat_pay, i.tevkifat_payda, i.tevkifat_kurus, i.tutar_kurus, i.odenecek_kurus,
  i.kdv_indirilebilir, i.status, i.paid_at::text AS paid_at, i.note, i.created_by, i.created_at, i.updated_at`;

function serialize(row, ref, today) {
  const overdue = OPEN.includes(row.status) && !!row.due_date && row.due_date < today;
  return {
    ...row,
    tevkifat_oran: row.tevkifat_pay ? `${row.tevkifat_pay}/${row.tevkifat_payda}` : null,
    invoice_type_label: TYPE_TR[row.invoice_type], status_label: STATUS_TR[row.status],
    overdue, days_overdue: overdue ? daysBetween(row.due_date, today) : 0,
    confirmation: C.invoiceConfirmation(row, ref),
  };
}
async function loadOne(id, ledger) {
  const { rows } = await db.query(`SELECT ${COLS} FROM invoices i WHERE i.id = $1`, [id]);
  if (!rows[0]) throw C.httpError(404, "Fatura bulunamadı.");
  if (String(rows[0].owner_id) !== String(ledger)) throw C.httpError(404, "Fatura bulunamadı.");
  return rows[0];
}

/** Kilitli KDV döneminde değişiklik yapılamaz */
async function assertPeriodsOpen(ledger, dates) {
  for (const d of [...new Set(dates.filter(Boolean))]) {
    const { rows } = await db.query("SELECT period_key FROM vat_periods WHERE owner_id = $1 AND status = 'kilitli' AND $2::date BETWEEN starts_on AND ends_on LIMIT 1", [ledger, d]);
    if (rows[0]) throw C.httpError(409, `KDV dönemi kilitli (${rows[0].period_key}); fatura değiştirilemez. Önce dönemin kilidini açın.`, { code: "vat_period_locked", period: rows[0].period_key });
  }
}

/** Tutar alanlarını çöz: {matrah_kurus, kdv_oran, kdv_kurus, tevkifat_pay, tevkifat_payda, tevkifat_kurus, tutar_kurus} | null (dokunulmamış) */
function resolveAmounts(body, existing, ref, issueDate, warnings) {
  const has = (k) => body[k] !== undefined;
  const wKeys = ["tevkifat", "tevkifat_oran", "tevkifat_pay", "tevkifat_payda"];
  const touched = ["matrah_kurus", "tutar_kurus", "kdv_kurus", "kdv_oran"].some(has) || wKeys.some(has);
  if (!existing && !has("matrah_kurus") && !has("tutar_kurus")) throw C.httpError(400, "matrah_kurus (KDV hariç) ya da tutar_kurus (KDV dahil toplam) zorunludur.");
  if (existing && !touched) return null;
  for (const k of ["matrah_kurus", "tutar_kurus", "kdv_kurus"]) if (has(k) && !isKurus(body[k])) throw C.httpError(400, `${k} 0 ile 10 milyar TL arasında kuruş TAMSAYISI olmalıdır.`);
  if (has("matrah_kurus") && has("tutar_kurus") && !has("kdv_kurus")) throw C.httpError(400, "matrah_kurus ve tutar_kurus birlikte verilecekse kdv_kurus da verilmelidir.");

  let rate;
  if (has("kdv_oran")) rate = body.kdv_oran;
  else if (existing) rate = existing.kdv_oran;
  else { const d = C.defaultRate(ref.rates); if (!d) throw C.httpError(400, "kdv_oran zorunludur (varsayılan KDV oranı tanımlı değil)."); rate = Number(d.rate); }
  if (V.rateToBp(rate) === null) throw C.httpError(400, "kdv_oran 0 ile 100 arasında (en çok 2 ondalık) olmalıdır.");
  rate = Number(rate);

  // tevkifat
  let w;
  if (has("tevkifat")) w = V.parseWithholding(body.tevkifat);
  else if (has("tevkifat_oran")) w = V.parseWithholding(body.tevkifat_oran);
  else if (has("tevkifat_pay") || has("tevkifat_payda")) w = body.tevkifat_pay == null && body.tevkifat_payda == null ? null : V.parseWithholding({ pay: body.tevkifat_pay, payda: body.tevkifat_payda });
  else w = existing && existing.tevkifat_pay ? { pay: existing.tevkifat_pay, payda: existing.tevkifat_payda } : null;
  if (w === undefined) throw C.httpError(400, "Geçersiz tevkifat oranı (örn. {\"pay\":4,\"payda\":10} ya da \"4/10\").");

  let matrah, kdv, tutar, tev;
  const keepKdv = existing && !has("kdv_kurus") && !has("matrah_kurus") && !has("tutar_kurus") && !has("kdv_oran");
  if (has("kdv_kurus") || keepKdv) {
    kdv = has("kdv_kurus") ? body.kdv_kurus : existing.kdv_kurus;
    if (has("matrah_kurus")) matrah = body.matrah_kurus;
    else if (has("tutar_kurus")) matrah = body.tutar_kurus - kdv;
    else matrah = existing.matrah_kurus;
    if (matrah < 0) throw C.httpError(400, "tutar_kurus, kdv_kurus'tan küçük olamaz.");
    tutar = matrah + kdv;
    if (has("matrah_kurus") && has("tutar_kurus") && body.tutar_kurus !== tutar) throw C.httpError(400, "matrah_kurus + kdv_kurus, tutar_kurus'a eşit olmalıdır.", { code: "total_mismatch", expectedTutarKurus: tutar });
    const chk = V.checkDeclaredVat({ matrahKurus: matrah, kdvKurus: kdv, rate });
    if (!chk.ok && body.accept_mismatch !== true) {
      throw C.httpError(400, `KDV tutarı matrah × oran ile uyuşmuyor (fark ${chk.diff} kuruş; tolerans ${V.VAT_TOLERANCE_KURUS}). Belgedeki değer doğruysa accept_mismatch:true gönderin.`, { code: "kdv_mismatch", expectedKdvKurus: chk.expected, diffKurus: chk.diff });
    }
    if (!chk.ok) warnings.push({ code: "kdv_mismatch_accepted", message: `KDV tutarı matrah × oran ile ${chk.diff} kuruş farklı (kabul edildi).` });
    tev = w ? mulDiv(kdv, w.pay, w.payda) : 0;
  } else {
    const mode = has("tutar_kurus") ? "dahil" : "haric";
    const amountKurus = has("tutar_kurus") ? body.tutar_kurus : has("matrah_kurus") ? body.matrah_kurus : existing.matrah_kurus;
    const r = V.computeInvoiceAmounts({ mode, amountKurus, rate, withholding: w });
    if (r.error) throw C.httpError(400, r.error);
    ({ matrahKurus: matrah, kdvKurus: kdv, tutarKurus: tutar, tevkifatKurus: tev } = r);
  }
  if (!C.findRate(ref.rates, rate, issueDate)) warnings.push({ code: "kdv_rate_not_listed", message: `%${rate} oranı KDV oran listesinde (vat_rates) yok veya bu tarihte geçerli değil; mali müşavire teyit edin.` });
  return { matrah_kurus: matrah, kdv_oran: rate, kdv_kurus: kdv, tevkifat_pay: w ? w.pay : null, tevkifat_payda: w ? w.payda : null, tevkifat_kurus: tev, tutar_kurus: tutar };
}

async function buildFields(req, body, existing, ledger, ref, warnings) {
  const out = {};
  const create = !existing;
  if (create || body.direction !== undefined) out.direction = C.oneOf(body.direction, DIRECTIONS, "direction");
  if (body.invoice_type !== undefined) out.invoice_type = C.oneOf(body.invoice_type, TYPES, "invoice_type");
  else if (create) out.invoice_type = "diger";
  if (body.status !== undefined) out.status = C.oneOf(body.status, STATUSES, "status");
  else if (create) out.status = "kesildi";
  const txt = (k, max) => { const v = C.optText(body[k], k, max); if (v !== undefined) out[k] = v; };
  txt("invoice_no", 64); txt("ettn", 64); txt("counterparty", 200); txt("note", 2000); txt("kdv_istisna_nedeni", 200);
  const issue = C.optDate(body.issue_date, "issue_date");
  if (issue === null || (create && issue === undefined)) throw C.httpError(400, "issue_date zorunludur (YYYY-AA-GG).");
  if (issue !== undefined) out.issue_date = issue;
  const due = C.optDate(body.due_date, "due_date"); if (due !== undefined) out.due_date = due;
  const paid = C.optDate(body.paid_at, "paid_at"); if (paid !== undefined) out.paid_at = paid;
  const ind = C.optBool(body.kdv_indirilebilir, "kdv_indirilebilir"); if (ind !== undefined) out.kdv_indirilebilir = ind;
  if (body.counterparty_tax_id !== undefined) {
    const t = V.validateTaxId(body.counterparty_tax_id === "" ? null : body.counterparty_tax_id);
    if (!t.ok) throw C.httpError(400, "counterparty_tax_id 10 haneli VKN ya da 11 haneli TCKN olmalıdır.");
    out.counterparty_tax_id = t.empty ? null : t.value;
    if (!t.empty && !t.checksumOk) warnings.push({ code: "tax_id_checksum", message: `${t.kind} sağlama (checksum) kontrolünden geçmedi; numarayı belgeyle karşılaştırın.` });
  }
  // bağlantılar
  for (const [k, kind] of [["customer_id", "customer"], ["project_id", "project"], ["offer_id", "offer"], ["payment_id", "payment"], ["expense_id", "expense"]]) {
    const v = C.optUuid(body[k], k);
    if (v !== undefined) { if (v) await C.checkLink(req, kind, v, ledger); out[k] = v; }
  }
  const eff = { ...(existing || {}), ...out };
  const effIssue = eff.issue_date;
  const amt = resolveAmounts(body, existing, ref, effIssue, warnings);
  if (amt) Object.assign(out, amt);
  if (eff.due_date && effIssue && eff.due_date < effIssue) warnings.push({ code: "due_before_issue", message: "Vade tarihi fatura tarihinden önce." });
  if (out.status === "odendi" && !eff.paid_at && out.paid_at === undefined) out.paid_at = C.today();
  if (out.status && out.status !== "odendi" && existing && existing.status === "odendi" && out.paid_at === undefined) out.paid_at = null;
  return out;
}

/** Aynı defter+yön+belge no+karşı taraf (iptal dışında) → yinelenen kayıt uyarısı */
async function duplicateWarning(ledger, inv, selfId) {
  if (!inv.invoice_no) return null;
  const { rows } = await db.query(
    `SELECT id FROM invoices WHERE owner_id = $1 AND direction = $2 AND lower(invoice_no) = lower($3) AND status <> 'iptal'
       AND lower(COALESCE(counterparty,'')) = lower($4) AND ($5::uuid IS NULL OR id <> $5) LIMIT 1`,
    [ledger, inv.direction, inv.invoice_no, inv.counterparty || "", selfId || null]);
  return rows[0] ? { code: "duplicate_invoice_no", message: "Aynı belge numarası ve karşı tarafla başka bir kayıt var.", existing_id: rows[0].id } : null;
}

const counted = (s) => VP.COUNTED_STATUSES.includes(s);
const VAT_FIELDS = ["direction", "issue_date", "matrah_kurus", "kdv_oran", "kdv_kurus", "tevkifat_kurus", "kdv_indirilebilir"];

// -------------------------------------------------------------------- liste / özet / dışa aktarma
function filters(req, ledger) {
  const q = req.query; const params = [ledger]; let where = "i.owner_id = $1";
  const add = (sql, v) => { params.push(v); where += ` AND ${sql.replace("?", "$" + params.length)}`; };
  if (q.direction !== undefined) add("i.direction = ?", C.oneOf(q.direction, DIRECTIONS, "direction"));
  if (q.status !== undefined) {
    const list = String(q.status).split(",").map((s) => s.trim()).filter(Boolean);
    list.forEach((s) => C.oneOf(s, STATUSES, "status"));
    add("i.status = ANY(?::text[])", list);
  }
  if (q.invoice_type !== undefined) add("i.invoice_type = ?", C.oneOf(q.invoice_type, TYPES, "invoice_type"));
  if (q.period !== undefined) { const r = C.periodRange(q.period); if (!r) throw C.httpError(400, "period YYYY, YYYY-AA ya da YYYY-Qn olmalıdır."); add("i.issue_date >= ?::date", r.from); add("i.issue_date <= ?::date", r.to); }
  for (const [k, col, op] of [["from", "i.issue_date", ">="], ["to", "i.issue_date", "<="], ["due_from", "i.due_date", ">="], ["due_to", "i.due_date", "<="]]) {
    if (q[k] !== undefined) { if (!C.optDate(q[k], k)) throw C.httpError(400, `${k} geçersiz.`); add(`${col} ${op} ?::date`, q[k]); }
  }
  if (q.overdue === "1" || q.overdue === "true") { add("i.status = ANY(?::text[])", OPEN); add("i.due_date < ?::date", C.today()); }
  if (q.unpaid === "1" || q.unpaid === "true") add("i.status = ANY(?::text[])", OPEN);
  for (const k of ["project_id", "customer_id", "offer_id"]) if (q[k] !== undefined) { if (!C.isUuid(q[k])) throw C.httpError(400, `${k} geçersiz.`); add(`i.${k} = ?`, q[k]); }
  return { where, params };
}

router.get("/", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req);
  const pg = parseListParams(req);
  const { where, params } = filters(req, ledger);
  let sql = `SELECT ${COLS}, (SELECT COUNT(*)::int FROM invoice_files f WHERE f.invoice_id = i.id) AS file_count FROM invoices i WHERE ${where}`;
  sql += searchClause(pg, ["i.invoice_no", "i.counterparty", "i.note"], null, params);
  const result = await queryList(sql, params, "ORDER BY i.issue_date DESC, i.created_at DESC", pg);
  const ref = await C.loadRates(await C.orgOf(req)); const today = C.today();
  sendList(res, pg, { rows: result.rows.map((r) => serialize(r, ref, today)), total: result.total });
}));

/** KDV'ye esas özet: dönem içi giden/gelen toplamları + açık (tahsil edilmemiş/ödenmemiş) tutar */
router.get("/summary", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req);
  if (req.query.period === undefined) throw C.httpError(400, "period zorunludur (YYYY, YYYY-AA ya da YYYY-Qn).");
  const { where, params } = filters(req, ledger);
  const { rows } = await db.query(
    `SELECT i.direction, i.status, COUNT(*)::int AS n, COALESCE(SUM(i.matrah_kurus),0)::bigint AS matrah, COALESCE(SUM(i.kdv_kurus),0)::bigint AS kdv,
            COALESCE(SUM(i.tevkifat_kurus),0)::bigint AS tevkifat, COALESCE(SUM(i.tutar_kurus),0)::bigint AS tutar, COALESCE(SUM(i.odenecek_kurus),0)::bigint AS odenecek
       FROM invoices i WHERE ${where} GROUP BY 1, 2`, params);
  const blank = () => ({ count: 0, matrahKurus: 0, kdvKurus: 0, tevkifatKurus: 0, tutarKurus: 0, odenecekKurus: 0, acikKurus: 0 });
  const out = { period: req.query.period, giden: blank(), gelen: blank(), byStatus: {} };
  for (const r of rows) {
    (out.byStatus[r.status] ||= { count: 0, tutarKurus: 0 }); out.byStatus[r.status].count += r.n; out.byStatus[r.status].tutarKurus += Number(r.tutar);
    if (!counted(r.status)) continue; // taslak/iptal toplamlara girmez
    const d = out[r.direction]; d.count += r.n; d.matrahKurus += Number(r.matrah); d.kdvKurus += Number(r.kdv); d.tevkifatKurus += Number(r.tevkifat); d.tutarKurus += Number(r.tutar); d.odenecekKurus += Number(r.odenecek);
    if (OPEN.includes(r.status)) d.acikKurus += Number(r.odenecek);
  }
  out.note = "Taslak ve iptal faturalar toplamlara dahil değildir. Tahmini/izleme amaçlıdır; mali müşavire teyit edin.";
  res.json(out);
}));

/** Muhasebeci dışa aktarımı: GET /api/invoices/export?period=2026-10&format=csv|xlsx[&direction=][&status=][&include=all] */
router.get("/export", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req);
  const format = req.query.format === undefined ? "csv" : C.oneOf(req.query.format, ["csv", "xlsx"], "format");
  if (req.query.period === undefined) throw C.httpError(400, "period zorunludur (YYYY, YYYY-AA ya da YYYY-Qn).");
  const q = { ...req.query };
  if (q.status === undefined && q.include !== "all") q.status = "kesildi,gonderildi,odendi"; // taslak/iptal varsayılan olarak dışarıda
  const { where, params } = filters({ query: q }, ledger);
  const { rows } = await db.query(`SELECT ${COLS}, pr.code AS project_code FROM invoices i LEFT JOIN projects pr ON pr.id = i.project_id WHERE ${where} ORDER BY i.issue_date, i.invoice_no NULLS LAST, i.created_at LIMIT ${EXPORT_MAX_ROWS + 1}`, params);
  if (rows.length > EXPORT_MAX_ROWS) throw C.httpError(413, `Dışa aktarılacak kayıt çok fazla (en çok ${EXPORT_MAX_ROWS}); dönemi daraltın.`);
  const ref = await C.loadRates(await C.orgOf(req));
  // Sütunlar araştırma §2.5 önerisine göre; tek KDV oranı/belge modeli: matrah+oran+KDV yan yana (muhasebeci pivotlar). Para birimi yalnız TL.
  const columns = [
    { header: "Tarih", type: "date", width: 12 }, { header: "Belge Türü", type: "text", width: 20 }, { header: "Belge No", type: "text", width: 18 },
    { header: "ETTN", type: "text", width: 38 }, { header: "Yön", type: "text", width: 8 }, { header: "Karşı Taraf Unvan", type: "text", width: 30 },
    { header: "VKN/TCKN", type: "text", width: 13 }, { header: "Matrah", type: "money", width: 14 }, { header: "KDV Oranı (%)", type: "percent", width: 12 },
    { header: "KDV", type: "money", width: 14 }, { header: "Tevkifat Oranı", type: "text", width: 12 }, { header: "Tevkifat Tutarı", type: "money", width: 14 },
    { header: "Genel Toplam", type: "money", width: 14 }, { header: "Ödenecek", type: "money", width: 14 }, { header: "Para Birimi", type: "text", width: 8 },
    { header: "Proje Kodu", type: "text", width: 12 }, { header: "Açıklama", type: "text", width: 40 }, { header: "Durum", type: "text", width: 11 },
    { header: "Vade", type: "date", width: 12 }, { header: "İndirilebilir KDV (E/H)", type: "text", width: 12 }, { header: "Dönem", type: "text", width: 9 },
    { header: "Teyit Gerekli (E/H)", type: "text", width: 12 },
  ];
  const data = rows.map((r) => [
    r.issue_date, TYPE_TR[r.invoice_type], r.invoice_no, r.ettn, r.direction === "giden" ? "Giden" : "Gelen", r.counterparty, r.counterparty_tax_id,
    r.matrah_kurus, Number(r.kdv_oran), r.kdv_kurus, r.tevkifat_pay ? `${r.tevkifat_pay}/${r.tevkifat_payda}` : null, r.tevkifat_kurus || 0,
    r.tutar_kurus, r.odenecek_kurus, "TRY", r.project_code, r.note, STATUS_TR[r.status], r.due_date,
    r.direction === "gelen" ? (r.kdv_indirilebilir ? "E" : "H") : "", r.issue_date.slice(0, 7), C.invoiceConfirmation(r, ref).needed ? "E" : "H",
  ]);
  const label = String(req.query.period).replace(/[^\w-]/g, "");
  res.setHeader("Cache-Control", "private, no-store");
  res.setHeader("X-Needs-Confirmation", "true"); // oran/takvim doğrulaması mali müşavirde
  if (format === "csv") {
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader("Content-Disposition", `attachment; filename="faturalar-${label}.csv"`);
    return res.send(toCsv(columns, data));
  }
  const sum = VP.summarizeInvoices(rows.map((r) => ({ ...r, kdv_oran: Number(r.kdv_oran) })));
  const sumCols = [{ header: "Yön", type: "text", width: 10 }, { header: "KDV Oranı (%)", type: "percent", width: 12 }, { header: "Belge Adedi", type: "int", width: 12 },
    { header: "Matrah", type: "money", width: 16 }, { header: "KDV", type: "money", width: 16 }, { header: "Tevkifat", type: "money", width: 16 }];
  const sumRows = [];
  for (const dir of ["giden", "gelen"]) for (const b of sum.byRate[dir]) sumRows.push([dir === "giden" ? "Giden" : "Gelen", b.rate, b.count, b.matrahKurus, b.kdvKurus, b.tevkifatKurus]);
  res.setHeader("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
  res.setHeader("Content-Disposition", `attachment; filename="faturalar-${label}.xlsx"`);
  res.send(toXlsx([{ name: "Faturalar", columns, rows: data }, { name: "Özet", columns: sumCols, rows: sumRows }]));
}));

// -------------------------------------------------------------------- CRUD
router.post("/", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req);
  const ref = await C.loadRates(await C.orgOf(req)); const warnings = [];
  const f = await buildFields(req, req.body || {}, null, ledger, ref, warnings);
  if (counted(f.status)) await assertPeriodsOpen(ledger, [f.issue_date]);
  const dup = await duplicateWarning(ledger, f, null); if (dup) warnings.push(dup);
  const cols = Object.keys(f);
  const { rows } = await db.query(
    `INSERT INTO invoices (owner_id, org_id, created_by, ${cols.join(", ")}) VALUES ($1, $2, $3, ${cols.map((_, i) => "$" + (i + 4)).join(", ")}) RETURNING id`,
    [ledger, await orgIdForUser(ledger), req.user.id, ...cols.map((c) => f[c])]);
  const row = await loadOne(rows[0].id, ledger);
  audit(req, "invoice.create", rows[0].id, { direction: f.direction, invoice_no: f.invoice_no || null });
  res.status(201).json({ ...serialize(row, ref, C.today()), files: [], warnings });
}));

router.get("/:id", C.guard, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const ledger = await C.ledgerOf(req);
  const row = await loadOne(req.params.id, ledger);
  const files = (await db.query("SELECT id, invoice_id, file_url, file_name, uploaded_by, created_at FROM invoice_files WHERE invoice_id = $1 ORDER BY created_at", [row.id])).rows;
  res.json({ ...serialize(row, await C.loadRates(await C.orgOf(req)), C.today()), files: files.map((f) => signRow(f, "file_url")) });
}));

router.patch("/:id", C.guard, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const ledger = await C.ledgerOf(req);
  const existing = await loadOne(req.params.id, ledger);
  const ref = await C.loadRates(await C.orgOf(req)); const warnings = [];
  const f = await buildFields(req, req.body || {}, existing, ledger, ref, warnings);
  if (Object.keys(f).length === 0) throw C.httpError(400, "Güncellenecek alan yok.");
  const next = { ...existing, ...f };
  const vatTouched = VAT_FIELDS.some((k) => k in f && String(f[k]) !== String(existing[k])) || counted(existing.status) !== counted(next.status);
  if (vatTouched && (counted(existing.status) || counted(next.status))) await assertPeriodsOpen(ledger, [existing.issue_date, next.issue_date]);
  const dup = await duplicateWarning(ledger, next, existing.id); if (dup) warnings.push(dup);
  const cols = Object.keys(f);
  await db.query(`UPDATE invoices SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(", ")}, updated_at = now() WHERE id = $${cols.length + 1}`, [...cols.map((c) => f[c]), existing.id]);
  audit(req, "invoice.update", existing.id, { fields: cols });
  res.json({ ...serialize(await loadOne(existing.id, ledger), ref, C.today()), warnings });
}));

router.delete("/:id", C.guard, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const ledger = await C.ledgerOf(req);
  const row = await loadOne(req.params.id, ledger);
  if (!["taslak", "iptal"].includes(row.status)) throw C.httpError(409, "Kesilmiş/gönderilmiş/ödenmiş fatura silinemez; önce durumunu 'iptal' yapın.");
  const files = (await db.query("SELECT file_url FROM invoice_files WHERE invoice_id = $1", [row.id])).rows;
  await db.query("DELETE FROM invoices WHERE id = $1", [row.id]);
  for (const f of files) removeStored(f.file_url);
  audit(req, "invoice.delete", row.id, { invoice_no: row.invoice_no || null });
  res.json({ message: "Silindi." });
}));

// -------------------------------------------------------------------- ödendi işaretle
router.post("/:id/mark-paid", C.guard, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const ledger = await C.ledgerOf(req);
  const inv = await loadOne(req.params.id, ledger);
  const b = req.body || {};
  if (inv.status === "odendi") throw C.httpError(409, "Fatura zaten ödendi olarak işaretli.");
  if (!OPEN.includes(inv.status)) throw C.httpError(409, `'${STATUS_TR[inv.status]}' durumundaki fatura ödendi yapılamaz.`);
  const paidAt = C.optDate(b.paid_at, "paid_at") || C.today();
  const method = b.method === undefined ? "Havale" : C.oneOf(b.method, METHODS, "method");
  const paymentId = C.optUuid(b.payment_id, "payment_id");
  if (paymentId) await C.checkLink(req, "payment", paymentId, ledger);
  const expenseId = C.optUuid(b.expense_id, "expense_id");
  if (expenseId) await C.checkLink(req, "expense", expenseId, ledger);
  if (b.create_payment === true) {
    if (inv.direction !== "giden" || !inv.project_id) throw C.httpError(400, "create_payment yalnız projeye bağlı GİDEN faturada kullanılabilir.");
    if (paymentId) throw C.httpError(400, "create_payment ile payment_id birlikte verilemez.");
  }
  const client = await db.pool.connect();
  let createdPayment = null, closed = 0;
  try {
    await client.query("BEGIN");
    let linkPayment = paymentId || inv.payment_id;
    if (b.create_payment === true) {
      // Mevcut payments tablosu NUMERIC TL: kuruş → TL dönüşümü. Tahsilat = tevkifat düşülmüş tutar (alıcıdan alınacak).
      const p = await client.query(
        "INSERT INTO payments (project_id, amount, method, note, paid_at, owner_id) VALUES ($1,$2,$3,$4,$5::timestamptz,$6) RETURNING id, amount",
        [inv.project_id, fromKurus(inv.odenecek_kurus), method, `Fatura ${inv.invoice_no || inv.id.slice(0, 8)} ödendi`, `${paidAt}T12:00:00+03:00`, ledger]);
      createdPayment = p.rows[0]; linkPayment = createdPayment.id;
    }
    await client.query("UPDATE invoices SET status = 'odendi', paid_at = $1, payment_id = $2, expense_id = COALESCE($3, expense_id), updated_at = now() WHERE id = $4", [paidAt, linkPayment, expenseId, inv.id]);
    // Faturaya bağlı bekleyen taksitler de kapanır (fatura tamamen ödendi)
    const r = await client.query("UPDATE payment_schedule SET status = 'odendi', paid_at = $1, updated_at = now() WHERE invoice_id = $2 AND status = 'bekliyor'", [paidAt, inv.id]);
    closed = r.rowCount;
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
  audit(req, "invoice.mark_paid", inv.id, { created_payment: !!createdPayment });
  res.json({ ...serialize(await loadOne(inv.id, ledger), await C.loadRates(await C.orgOf(req)), C.today()), created_payment: createdPayment, schedule_items_closed: closed });
}));

// -------------------------------------------------------------------- ekler (fatura fotoğrafı / PDF)
const INVOICE_DIR = path.join(UPLOAD_DIR, "invoices");
if (!fs.existsSync(INVOICE_DIR)) fs.mkdirSync(INVOICE_DIR, { recursive: true });
const ALLOWED_EXT = new Set([".pdf", ".png", ".jpg", ".jpeg", ".webp", ".gif", ".heic", ".heif"]);
const extOf = (n) => path.extname(String(n || "")).toLowerCase();
const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, INVOICE_DIR),
    filename: (req, file, cb) => {
      const stem = path.basename(file.originalname, path.extname(file.originalname)).replace(/[^\w\-]+/g, "_").slice(0, 50) || "fatura";
      cb(null, `${Date.now()}-${crypto.randomBytes(6).toString("hex")}-${stem}${extOf(file.originalname)}`);
    },
  }),
  limits: { fileSize: 15 * 1024 * 1024, files: 1, fields: 5, parts: 8 },
  fileFilter: (req, file, cb) => (ALLOWED_EXT.has(extOf(file.originalname)) ? cb(null, true) : cb(Object.assign(new Error("Bu dosya türü yüklenemez."), { status: 400 }))),
});
const uploadLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 120, keyGenerator: (req) => (req.user ? "u:" + req.user.id : "ip"), message: { error: "Çok fazla dosya yükleme isteği. Lütfen biraz sonra tekrar deneyin." } });
const removeStored = (url) => { const rel = relFromStored(url); if (rel && rel.startsWith("invoices/")) { const abs = path.resolve(UPLOAD_DIR, rel); if (abs.startsWith(path.resolve(INVOICE_DIR) + path.sep)) { try { fs.unlinkSync(abs); } catch {} } } };

// Yetki + sayı kontrolü dosya diske yazılmadan ÖNCE (yetkisiz isteklerle disk doldurulamaz)
const precheck = C.wrap(async (req, res, next) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const inv = await loadOne(req.params.id, await C.ledgerOf(req));
  const n = (await db.query("SELECT COUNT(*)::int AS n FROM invoice_files WHERE invoice_id = $1", [inv.id])).rows[0].n;
  if (n >= MAX_FILES) throw C.httpError(409, `Bir faturaya en çok ${MAX_FILES} dosya eklenebilir.`);
  next();
});
router.post("/:id/files", C.guard, uploadLimiter, precheck, upload.single("file"), C.wrap(async (req, res) => {
  if (!req.file) throw C.httpError(400, "Dosya bulunamadı.");
  if (!contentMatchesExt(req.file.path, extOf(req.file.filename))) { try { fs.unlinkSync(req.file.path); } catch {} throw C.httpError(400, "Dosya içeriği uzantısıyla uyuşmuyor; yüklenemez."); }
  const orig = String(req.file.originalname || "fatura").replace(/[\u0000-\u001f\u007f<>]/g, "").slice(0, 200);
  const url = `${String(process.env.APP_URL || "").replace(/\/+$/, "")}/uploads/invoices/${req.file.filename}`;
  let rows;
  try { ({ rows } = await db.query("INSERT INTO invoice_files (invoice_id, file_url, file_name, uploaded_by) VALUES ($1,$2,$3,$4) RETURNING *", [req.params.id, url, orig, req.user.id])); }
  catch (e) { try { fs.unlinkSync(req.file.path); } catch {} throw e; }
  res.status(201).json(signRow(rows[0], "file_url"));
}));

async function loadFile(req) {
  const ledger = await C.ledgerOf(req);
  if (!C.isUuid(req.params.id) || !C.isUuid(req.params.fileId)) throw C.httpError(400, "Geçersiz değer girildi.");
  await loadOne(req.params.id, ledger);
  const { rows } = await db.query("SELECT * FROM invoice_files WHERE id = $1 AND invoice_id = $2", [req.params.fileId, req.params.id]);
  if (!rows[0]) throw C.httpError(404, "Dosya bulunamadı.");
  return rows[0];
}
router.get("/:id/files/:fileId", C.guard, C.wrap(async (req, res) => {
  const f = await loadFile(req);
  const rel = relFromStored(f.file_url);
  const abs = rel && path.resolve(UPLOAD_DIR, rel);
  if (!abs || !abs.startsWith(path.resolve(INVOICE_DIR) + path.sep) || !fs.existsSync(abs)) throw C.httpError(404, "Dosya bulunamadı.");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Cache-Control", "private, no-store");
  const inline = [".pdf", ".png", ".jpg", ".jpeg", ".webp", ".gif"].includes(extOf(abs));
  res.setHeader("Content-Disposition", `${inline ? "inline" : "attachment"}; filename="${path.basename(abs).replace(/[^\w.\-]/g, "_")}"`);
  res.sendFile(abs, { dotfiles: "deny" });
}));
router.delete("/:id/files/:fileId", C.guard, C.wrap(async (req, res) => {
  const f = await loadFile(req);
  await db.query("DELETE FROM invoice_files WHERE id = $1", [f.id]);
  removeStored(f.file_url);
  res.json({ message: "Silindi." });
}));

module.exports = router;
module.exports._test = { resolveAmounts, STATUS_TR, TYPE_TR };
