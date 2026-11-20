/**
 * /api/vat — KDV oranları/tevkifat türleri (veri), dönem özeti (hesapla/özet/kilitle), dışa aktarım ve M7/M8 içgörüleri.
 * Tüm KDV çıktıları TAHMİNİDİR; her yanıt "needs_confirmation" ve nedenlerini taşır (mali müşavire teyit).
 */
const express = require("express");
const C = require("./common");
const { db } = C;
const VP = require("../../assistant/tax/vatPeriod");
const VS = require("../../assistant/tax/vatService");
const V = require("../../assistant/tax/vat");
const R = require("../../assistant/tax/rules");
const { toKurus } = require("../../assistant/tax/money");
const { toCsv, toXlsx } = require("../../assistant/tax/exportFile");
const { addDays } = require("../../assistant/tax/dates");

const { logAction } = require("../../assistant/audit");
const router = express.Router();

// ---------------------------------------------------------------- oranlar (referans verisi)
const withFlags = (r) => ({ ...r, needs_confirmation: !r.verified });
router.get("/rates", C.guard, C.wrap(async (req, res) => {
  const ref = await C.loadRates(await C.orgOf(req));
  res.json({
    rates: ref.rates.map((r) => withFlags({ ...r, valid_from: r.valid_from ? String(r.valid_from).slice(0, 10) : null, valid_to: r.valid_to ? String(r.valid_to).slice(0, 10) : null })),
    withholding_types: ref.withholding.map((t) => withFlags({ ...t, label_ratio: `${t.pay}/${t.payda}` })),
    disclaimer: "Oranlar ve tevkifat türleri kullanıcı/mali müşavir tarafından düzenlenebilen VERİDİR; 'doğrulandı' işaretlenene kadar mali müşavire teyit gerekir. Hukuki/mali tavsiye değildir.",
  });
}));

function rateFields(b, create) {
  const out = {};
  if (create || b.rate !== undefined) { if (V.rateToBp(b.rate) === null) throw C.httpError(400, "rate 0 ile 100 arasında (en çok 2 ondalık) olmalıdır."); out.rate = Number(b.rate); }
  const l = C.optText(b.label, "label", 200); if (create && !l) throw C.httpError(400, "label zorunludur."); if (l !== undefined) out.label = l;
  const code = C.optText(b.code, "code", 60); if (create && !code) throw C.httpError(400, "code zorunludur."); if (code) { if (!/^[a-z0-9_]{2,60}$/.test(code)) throw C.httpError(400, "code küçük harf/rakam/alt çizgi olmalıdır."); out.code = code; }
  for (const k of ["is_default", "enabled", "verified"]) { const v = C.optBool(b[k], k); if (v !== undefined) out[k] = v; }
  for (const k of ["valid_from", "valid_to"]) { const v = C.optDate(b[k], k); if (v !== undefined) out[k] = v; }
  for (const k of ["source", "note"]) { const v = C.optText(b[k], k, 1000); if (v !== undefined) out[k] = v; }
  return out;
}
async function writeRow(table, id, fields, req, orgId) {
  if (fields.verified !== undefined) { fields.verified_by = fields.verified ? req.user.id : null; fields.verified_at = fields.verified ? new Date() : null; }
  const cols = Object.keys(fields);
  if (!id) {
    try {
      const { rows } = await db.query(`INSERT INTO ${table} (org_id, ${cols.join(",")}) VALUES ($${cols.length + 1}, ${cols.map((_, i) => "$" + (i + 1)).join(",")}) RETURNING *`, [...cols.map((c) => fields[c]), orgId]);
      return rows[0];
    } catch (e) { if (e.code === "23505") throw C.httpError(409, "Bu kodla (code) bir kayıt zaten var."); throw e; }
  }
  if (!cols.length) throw C.httpError(400, "Güncellenecek alan yok.");
  try {
    const { rows } = await db.query(`UPDATE ${table} SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(",")}, updated_at = now() WHERE id = $${cols.length + 1} AND org_id = $${cols.length + 2} RETURNING *`, [...cols.map((c) => fields[c]), id, orgId]);
    if (!rows[0]) throw C.httpError(404, "Kayıt bulunamadı.");
    return rows[0];
  } catch (e) { if (e.code === "23505") throw C.httpError(409, "Bu kodla (code) bir kayıt zaten var."); throw e; }
}
async function clearOtherDefaults(id, orgId) { await db.query("UPDATE vat_rates SET is_default = false WHERE id <> $1 AND org_id = $2 AND is_default", [id, orgId]); }

router.post("/rates", C.staffOnly, C.wrap(async (req, res) => {
  const f = rateFields(req.body || {}, true);
  if (f.verified === undefined) f.verified = false;
  const orgId = await C.orgOf(req);
  const row = await writeRow("vat_rates", null, f, req, orgId);
  if (row.is_default) await clearOtherDefaults(row.id, orgId);
  res.status(201).json(withFlags(row));
}));
router.patch("/rates/:id", C.staffOnly, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const orgId = await C.orgOf(req);
  const f = rateFields(req.body || {}, false);
  if ("rate" in f && f.verified === undefined) f.verified = false; // oran değişti → yeniden teyit gerekir
  const row = await writeRow("vat_rates", req.params.id, f, req, orgId);
  if (row.is_default) await clearOtherDefaults(row.id, orgId);
  res.json(withFlags(row));
}));
router.delete("/rates/:id", C.staffOnly, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const r = await db.query("DELETE FROM vat_rates WHERE id = $1 AND org_id = $2", [req.params.id, await C.orgOf(req)]);
  if (!r.rowCount) throw C.httpError(404, "Kayıt bulunamadı.");
  res.json({ message: "Silindi." });
}));

function whFields(b, create) {
  const out = {};
  if (create || b.pay !== undefined || b.payda !== undefined) {
    const w = V.parseWithholding({ pay: b.pay, payda: b.payda });
    if (!w) throw C.httpError(400, "pay ve payda 1-100 arası tamsayı olmalı, pay ≤ payda.");
    out.pay = w.pay; out.payda = w.payda;
  }
  const l = C.optText(b.label, "label", 300); if (create && !l) throw C.httpError(400, "label zorunludur."); if (l !== undefined) out.label = l;
  const code = C.optText(b.code, "code", 60); if (create && !code) throw C.httpError(400, "code zorunludur."); if (code) { if (!/^[a-z0-9_]{2,60}$/.test(code)) throw C.httpError(400, "code küçük harf/rakam/alt çizgi olmalıdır."); out.code = code; }
  for (const k of ["enabled", "verified"]) { const v = C.optBool(b[k], k); if (v !== undefined) out[k] = v; }
  for (const k of ["source", "note"]) { const v = C.optText(b[k], k, 1000); if (v !== undefined) out[k] = v; }
  return out;
}
router.post("/withholding-types", C.staffOnly, C.wrap(async (req, res) => {
  const f = whFields(req.body || {}, true); if (f.verified === undefined) f.verified = false;
  res.status(201).json(withFlags(await writeRow("vat_withholding_types", null, f, req, await C.orgOf(req))));
}));
router.patch("/withholding-types/:id", C.staffOnly, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const f = whFields(req.body || {}, false);
  if (("pay" in f || "payda" in f) && f.verified === undefined) f.verified = false;
  res.json(withFlags(await writeRow("vat_withholding_types", req.params.id, f, req, await C.orgOf(req))));
}));
router.delete("/withholding-types/:id", C.staffOnly, C.wrap(async (req, res) => {
  if (!C.isUuid(req.params.id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const r = await db.query("DELETE FROM vat_withholding_types WHERE id = $1 AND org_id = $2", [req.params.id, await C.orgOf(req)]);
  if (!r.rowCount) throw C.httpError(404, "Kayıt bulunamadı.");
  res.json({ message: "Silindi." });
}));

// ---------------------------------------------------------------- dönemler
const parseKey = (v) => { const p = VP.parsePeriodKey(v); if (!p) throw C.httpError(400, "Dönem YYYY-AA (aylık) ya da YYYY-Qn (3 aylık) olmalıdır."); return p; };

async function one(ledger, key) {
  const [p] = await VS.computeRange(ledger, key, key);
  const due = await VS.loadDueContext(await require("../../assistant/org").orgIdForUser(ledger), [p.year]);
  return VS.decorate(p, due);
}

router.get("/periods", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req);
  const year = req.query.year === undefined ? +C.today().slice(0, 4) : Number(req.query.year);
  if (!Number.isInteger(year) || year < 2000 || year > 2100) throw C.httpError(400, "year geçersiz.");
  const type = req.query.type === undefined ? "aylik" : C.oneOf(req.query.type, ["aylik", "uc_aylik"], "type");
  const first = type === "aylik" ? `${year}-01` : `${year}-Q1`, last = type === "aylik" ? `${year}-12` : `${year}-Q4`;
  const chain = await VS.computeRange(ledger, first, last);
  const due = await VS.loadDueContext(await C.orgOf(req), [year]);
  res.json({ year, type, periods: chain.map((p) => VS.decorate(p, due)), note: "Tahmini/izleme amaçlıdır; beyan sorumluluğu mali müşavirdedir." });
}));

router.get("/periods/:ym", C.guard, C.wrap(async (req, res) => {
  const p = parseKey(req.params.ym);
  res.json(await one(await C.ledgerOf(req), p.key));
}));

/** Hesapla ve anlık görüntüyü sakla (kilitli değilse). body: {note?, manual_carry_in_kurus?} */
router.post("/periods/:ym/calculate", C.guard, C.wrap(async (req, res) => {
  const p = parseKey(req.params.ym); const ledger = await C.ledgerOf(req); const b = req.body || {};
  const cur = await one(ledger, p.key);
  if (cur.status === "kilitli") throw C.httpError(409, "Dönem kilitli; önce kilidini açın.");
  let carry; if (b.manual_carry_in_kurus !== undefined) {
    if (b.manual_carry_in_kurus !== null && (!Number.isInteger(b.manual_carry_in_kurus) || b.manual_carry_in_kurus < 0)) throw C.httpError(400, "manual_carry_in_kurus 0 ya da pozitif kuruş tamsayısı (ya da null) olmalıdır.");
    carry = b.manual_carry_in_kurus;
  }
  const note = C.optText(b.note, "note", 2000);
  if (carry !== undefined) { await VS.saveSnapshot(ledger, cur, { lock: false, userId: req.user.id, note, manualCarry: carry }); }
  const fresh = await one(ledger, p.key); // manuel devir değiştiyse yeniden hesapla
  await VS.saveSnapshot(ledger, fresh, { lock: false, userId: req.user.id, note });
  res.json(await one(ledger, p.key));
}));

router.patch("/periods/:ym", C.guard, C.wrap(async (req, res) => {
  const p = parseKey(req.params.ym); const ledger = await C.ledgerOf(req); const b = req.body || {};
  if (b.note === undefined && b.manual_carry_in_kurus === undefined) throw C.httpError(400, "Güncellenecek alan yok (note, manual_carry_in_kurus).");
  const cur = await one(ledger, p.key);
  if (cur.status === "kilitli") throw C.httpError(409, "Dönem kilitli; önce kilidini açın.");
  let carry; if (b.manual_carry_in_kurus !== undefined) {
    if (b.manual_carry_in_kurus !== null && (!Number.isInteger(b.manual_carry_in_kurus) || b.manual_carry_in_kurus < 0)) throw C.httpError(400, "manual_carry_in_kurus 0 ya da pozitif kuruş tamsayısı (ya da null) olmalıdır.");
    carry = b.manual_carry_in_kurus;
  }
  await VS.saveSnapshot(ledger, cur, { lock: false, userId: req.user.id, note: C.optText(b.note, "note", 2000), manualCarry: carry });
  const fresh = await one(ledger, p.key);
  await VS.saveSnapshot(ledger, fresh, { lock: false, userId: req.user.id });
  res.json(await one(ledger, p.key));
}));

/** Dönemi hesapla + kilitle: o dönemdeki faturalar (KDV'yi etkileyen alanlar) artık değiştirilemez */
router.post("/periods/:ym/lock", C.guard, C.wrap(async (req, res) => {
  const p = parseKey(req.params.ym); const ledger = await C.ledgerOf(req);
  const cur = await one(ledger, p.key);
  if (cur.status === "kilitli") throw C.httpError(409, "Dönem zaten kilitli.");
  await VS.saveSnapshot(ledger, cur, { lock: true, userId: req.user.id, note: C.optText((req.body || {}).note, "note", 2000) });
  logAction({ req, action: "vat_period.lock", entityType: "vat_period", entityId: p.key }).catch(() => {});
  res.json(await one(ledger, p.key));
}));
router.post("/periods/:ym/unlock", C.guard, C.wrap(async (req, res) => {
  const p = parseKey(req.params.ym); const ledger = await C.ledgerOf(req);
  const r = await db.query("UPDATE vat_periods SET status = 'acik', locked_at = NULL, locked_by = NULL, computed_at = now() WHERE owner_id = $1 AND period_key = $2 AND status = 'kilitli'", [ledger, p.key]);
  if (!r.rowCount) throw C.httpError(409, "Dönem kilitli değil.");
  res.json(await one(ledger, p.key));
  logAction({ req, action: "vat_period.unlock", entityType: "vat_period", entityId: p.key }).catch(() => {});
}));

/** Dönem özeti dışa aktarımı: GET /api/vat/periods/:ym/export?format=csv|xlsx */
router.get("/periods/:ym/export", C.guard, C.wrap(async (req, res) => {
  const p = parseKey(req.params.ym); const ledger = await C.ledgerOf(req);
  const format = req.query.format === undefined ? "csv" : C.oneOf(req.query.format, ["csv", "xlsx"], "format");
  const d = await one(ledger, p.key);
  const cols = [{ header: "Bölüm", type: "text", width: 26 }, { header: "KDV Oranı (%)", type: "percent", width: 12 }, { header: "Belge Adedi", type: "int", width: 12 }, { header: "Matrah", type: "money", width: 16 }, { header: "KDV", type: "money", width: 16 }, { header: "Tevkifat", type: "money", width: 16 }];
  const rateRows = [];
  d.oran_kirilimi.giden.forEach((b) => rateRows.push(["Giden (hesaplanan)", b.rate, b.count, b.matrahKurus, b.kdvKurus, b.tevkifatKurus]));
  d.oran_kirilimi.gelen.forEach((b) => rateRows.push(["Gelen (indirilecek)", b.rate, b.count, b.matrahKurus, b.kdvKurus, b.tevkifatKurus]));
  const sumCols = [{ header: "Kalem", type: "text", width: 44 }, { header: "Tutar", type: "money", width: 18 }];
  const sumRows = [
    ["Hesaplanan KDV (giden KDV − tevkifat)", d.hesaplanan_kurus], ["İndirilecek KDV (gelen, indirilebilir)", d.indirilecek_kurus],
    ["Önceki dönemden devreden KDV", d.onceki_devreden_kurus], ["Ödenecek KDV (tahmini)", d.odenecek_kurus], ["Sonraki döneme devreden KDV", d.devreden_kurus],
    ["Bilgi: indirilemez işaretli gelen KDV", d.indirilemeyen_kurus], ["Bilgi: gelen faturalarda tevkifat (KDV-2)", d.kdv2_kurus], ["Bilgi: giden faturalarda tevkifat (alıcı beyan eder)", d.tevkifat_giden_kurus],
  ];
  res.setHeader("Cache-Control", "private, no-store"); res.setHeader("X-Needs-Confirmation", "true");
  if (format === "csv") {
    // tek düz tablo: özet kalemleri + oran kırılımı
    const flat = [...sumRows.map((r) => [r[0], null, null, null, r[1], null]), ...rateRows];
    res.setHeader("Content-Type", "text/csv; charset=utf-8");
    res.setHeader("Content-Disposition", `attachment; filename="kdv-ozeti-${p.key}.csv"`);
    return res.send(toCsv(cols, flat));
  }
  res.setHeader("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
  res.setHeader("Content-Disposition", `attachment; filename="kdv-ozeti-${p.key}.xlsx"`);
  res.send(toXlsx([{ name: "Özet", columns: sumCols, rows: sumRows }, { name: "Oran Kırılımı", columns: cols, rows: rateRows },
    { name: "Notlar", columns: [{ header: "Not", type: "text", width: 100 }], rows: d.confirmation_reasons.map((x) => [x]) }]));
}));

// ---------------------------------------------------------------- M7 / M8 içgörüleri
/** GET /api/vat/insights?asOf=YYYY-MM-DD&type=aylik&cash_forecast_kurus=…&since_days=180 */
router.get("/insights", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req);
  const today = C.optDate(req.query.asOf, "asOf") || C.today();
  const type = req.query.type === undefined ? "aylik" : C.oneOf(req.query.type, ["aylik", "uc_aylik"], "type");
  const since = Number(req.query.since_days === undefined ? 180 : req.query.since_days);
  if (!Number.isInteger(since) || since < 7 || since > 730) throw C.httpError(400, "since_days 7-730 arasında olmalıdır.");
  let cash = null;
  if (req.query.cash_forecast_kurus !== undefined) { cash = Number(req.query.cash_forecast_kurus); if (!Number.isInteger(cash) || cash < 0) throw C.httpError(400, "cash_forecast_kurus kuruş tamsayısı olmalıdır."); }

  // M8: bugünün dönemini izleyen ödeme için bir önceki dönem
  const cur = VP.periodOfDate(type, today);
  const prevKey = VP.previousPeriodKey(cur);
  const p = (await VS.computeRange(ledger, prevKey, prevKey))[0];
  const due = await VS.loadDueContext(await C.orgOf(req), [p.year, p.year + 1]);
  const dec = VS.decorate(p, due);
  const pp = VP.parsePeriodKey(prevKey);
  const e = (await db.query(
    `SELECT COUNT(*)::int AS n, COALESCE(SUM(e.amount),0)::numeric AS total,
            COUNT(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM invoices i WHERE i.expense_id = e.id AND i.status = ANY($4::text[])))::int AS docless_n,
            COALESCE(SUM(e.amount) FILTER (WHERE NOT EXISTS (SELECT 1 FROM invoices i WHERE i.expense_id = e.id AND i.status = ANY($4::text[]))),0)::numeric AS docless_total
       FROM expenses e WHERE e.owner_id = $1 AND e.scope IN ('dukkan','genel') AND e.expense_date >= $2::date AND e.expense_date < ($3::date + 1)`,
    [ledger, pp.startsOn, pp.endsOn, VP.COUNTED_STATUSES])).rows[0];
  const m8 = R.m8VatDeadline({ key: prevKey, odenecekKurus: dec.odenecek_kurus, hesaplananKurus: dec.hesaplanan_kurus, indirilecekKurus: dec.indirilecek_kurus, oncekiDevredenKurus: dec.onceki_devreden_kurus, devredenKurus: dec.devreden_kurus },
    { dueDate: dec.due_date, today, cashForecastKurus: cash, dueNeedsConfirmation: dec.confirmation_reasons.some((r) => /son gün|tatil/.test(r)),
      docless: { count: e.docless_n, total: e.n, amountKurus: Math.round(Number(e.docless_total) * 100), totalKurus: Math.round(Number(e.total) * 100) } });

  // M7: son since gündeki ödemeler (ledger) ↔ giden faturalar (KDV dahil brüt)
  const pays = (await db.query(
    `SELECT p.id AS project_id, p.code, p.customer_name, to_char(pay.paid_at AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM-DD') AS day, pay.amount
       FROM payments pay JOIN projects p ON p.id = pay.project_id
      WHERE pay.owner_id = $1 AND pay.paid_at >= ($2::date - $3::int)`, [ledger, today, since])).rows;
  const invs = (await db.query(
    `SELECT project_id, COALESCE(SUM(tutar_kurus),0)::bigint AS s FROM invoices WHERE owner_id = $1 AND direction = 'giden' AND status = ANY($2::text[]) AND project_id = ANY($3::uuid[]) GROUP BY 1`,
    [ledger, VP.COUNTED_STATUSES, [...new Set(pays.map((x) => x.project_id))]])).rows;
  const invBy = Object.fromEntries(invs.map((r) => [r.project_id, Number(r.s)]));
  const projects = {};
  for (const x of pays) {
    const day = x.day;
    const pr = (projects[x.project_id] ||= { project_id: x.project_id, code: x.code, customer_name: x.customer_name, payments: [], invoicedKurus: invBy[x.project_id] || 0 });
    pr.payments.push({ day, kurus: toKurus(x.amount) });
  }
  const m7 = R.m7UnbilledCollections(Object.values(projects), today);
  res.json({ asOf: today, m7, m8: m8 ? [m8] : [], m8_period: { key: prevKey, due_date: dec.due_date, odenecek_kurus: dec.odenecek_kurus }, note: "Tahmini kural çıktıları; eşikler başlangıç varsayımıdır." });
}));

module.exports = router;
