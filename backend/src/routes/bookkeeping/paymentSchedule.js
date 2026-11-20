/**
 * /api/payment-schedule — tahsilat planı: taksit / vade / çek-senet. Proje, teklif (ve isteğe bağlı fatura) başına.
 * Para: kuruş tamsayısı. "gecikti" durumu SAKLANMAZ; bekliyor + vadesi geçmiş → effective_status = 'gecikti' (her okumada türetilir).
 * Roller: admin/muhasebe/ortak (ortak kendi defteri); personel/saha 403.
 */
const express = require("express");
const C = require("./common");
const { db } = C;
const R = require("../../assistant/tax/receivables");
const { isKurus, fromKurus } = require("../../assistant/tax/money");
const { daysBetween } = require("../../assistant/tax/dates");
const { orgIdForUser } = require("../../assistant/org");
const reminderPlanner = require("../../assistant/tax/reminderPlanner");

const router = express.Router();
const KINDS = ["avans", "ara", "bakiye", "taksit", "cek", "senet"];
const METHODS = ["Havale", "Nakit", "Kredi Kartı", "Çek", "Senet"];
const STATUSES = ["bekliyor", "odendi", "iptal"];
const MAX_BULK = 60;

const COLS = `s.id, s.owner_id, s.org_id, s.project_id, s.offer_id, s.invoice_id, s.kind, s.amount_kurus, s.due_date::text AS due_date, s.method, s.status,
  s.paid_at::text AS paid_at, s.paid_payment_id, s.instrument_no, s.bank, s.installment_no, s.group_id, s.note, s.created_at, s.updated_at,
  COALESCE(p.customer_name, o.name, i.counterparty) AS customer_name, p.code AS project_code, o.code AS offer_code`;
const FROM = `FROM payment_schedule s LEFT JOIN projects p ON p.id = s.project_id LEFT JOIN offers o ON o.id = s.offer_id LEFT JOIN invoices i ON i.id = s.invoice_id`;

function serialize(r, today) {
  const eff = R.effectiveStatus(r, today);
  const diff = daysBetween(r.due_date, today);
  return { ...r, effective_status: eff, days_overdue: eff === "gecikti" ? diff : 0, days_until_due: r.status === "bekliyor" && diff <= 0 ? -diff : null };
}
async function loadOne(id, ledger) {
  if (!C.isUuid(id)) throw C.httpError(400, "Geçersiz değer girildi.");
  const { rows } = await db.query(`SELECT ${COLS} ${FROM} WHERE s.id = $1`, [id]);
  if (!rows[0]) throw C.httpError(404, "Plan satırı bulunamadı.");
  if (String(rows[0].owner_id) !== String(ledger)) throw C.httpError(404, "Plan satırı bulunamadı.");
  return rows[0];
}
async function links(req, b, ledger) {
  const out = {};
  for (const [k, kind] of [["project_id", "project"], ["offer_id", "offer"], ["invoice_id", "invoice"]]) {
    const v = C.optUuid(b[k], k);
    if (v !== undefined) { if (v) await C.checkLink(req, kind, v, ledger); out[k] = v; }
  }
  return out;
}
/** Çek/senet türü yöntemi belirler; tutarsızlık hata */
function methodFor(kind, method) {
  const forced = kind === "cek" ? "Çek" : kind === "senet" ? "Senet" : null;
  if (method === undefined || method === null) return forced;
  C.oneOf(method, METHODS, "method");
  if (forced && method !== forced) throw C.httpError(400, `kind '${kind}' için method '${forced}' olmalıdır.`);
  return method;
}

router.get("/", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req); const today = C.today(); const q = req.query;
  const params = [ledger]; let where = "s.owner_id = $1";
  const add = (sql, v) => { params.push(v); where += ` AND ${sql.replace("?", "$" + params.length)}`; };
  for (const k of ["project_id", "offer_id", "invoice_id"]) if (q[k] !== undefined) { if (!C.isUuid(q[k])) throw C.httpError(400, `${k} geçersiz.`); add(`s.${k} = ?`, q[k]); }
  if (q.status !== undefined) {
    if (q.status === "gecikti") { where += " AND s.status = 'bekliyor'"; add("s.due_date < ?::date", today); }
    else add("s.status = ?", C.oneOf(q.status, STATUSES, "status"));
  }
  if (q.overdue === "1" || q.overdue === "true") { where += " AND s.status = 'bekliyor'"; add("s.due_date < ?::date", today); }
  if (q.kind !== undefined) add("s.kind = ?", C.oneOf(q.kind, KINDS, "kind"));
  for (const [k, op] of [["from", ">="], ["to", "<="]]) if (q[k] !== undefined) { if (!C.optDate(q[k], k)) throw C.httpError(400, `${k} geçersiz.`); add(`s.due_date ${op} ?::date`, q[k]); }
  const { rows } = await db.query(`SELECT ${COLS} ${FROM} WHERE ${where} ORDER BY s.due_date, s.installment_no NULLS LAST, s.created_at`, params);
  res.json(rows.map((r) => serialize(r, today)));
}));

router.post("/", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req); const b = req.body || {};
  const l = await links(req, b, ledger);
  if (!l.project_id && !l.offer_id && !l.invoice_id) throw C.httpError(400, "project_id, offer_id ya da invoice_id'den en az biri zorunludur.");
  const kind = b.kind === undefined ? "taksit" : C.oneOf(b.kind, KINDS, "kind");
  if (!isKurus(b.amount_kurus) || b.amount_kurus < 1) throw C.httpError(400, "amount_kurus pozitif kuruş tamsayısı olmalıdır.");
  const due = C.optDate(b.due_date, "due_date"); if (!due) throw C.httpError(400, "due_date zorunludur (YYYY-AA-GG).");
  const method = methodFor(kind, b.method);
  const { rows } = await db.query(
    `INSERT INTO payment_schedule (owner_id, org_id, created_by, project_id, offer_id, invoice_id, kind, amount_kurus, due_date, method, instrument_no, bank, note, installment_no)
     VALUES ($1,$14,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING id`,
    [ledger, req.user.id, l.project_id || null, l.offer_id || null, l.invoice_id || null, kind, b.amount_kurus, due, method,
      C.optText(b.instrument_no, "instrument_no", 64) ?? null, C.optText(b.bank, "bank", 100) ?? null, C.optText(b.note, "note", 1000) ?? null,
      Number.isInteger(b.installment_no) && b.installment_no > 0 && b.installment_no < 1000 ? b.installment_no : null, await orgIdForUser(ledger)]);
  res.status(201).json(serialize(await loadOne(rows[0].id, ledger), C.today()));
}));

/** Taksit planı üret: {project_id|offer_id, total_kurus, count, first_due, interval_months?|interval_days?, kind?, method?, replace?} — kuruş artığı son taksite eklenir */
router.post("/generate", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req); const b = req.body || {};
  const l = await links(req, b, ledger);
  if (!l.project_id && !l.offer_id) throw C.httpError(400, "project_id ya da offer_id zorunludur.");
  const kind = b.kind === undefined ? "taksit" : C.oneOf(b.kind, ["avans", "ara", "bakiye", "taksit"], "kind");
  const first = C.optDate(b.first_due, "first_due"); if (!first) throw C.httpError(400, "first_due zorunludur (YYYY-AA-GG).");
  const method = methodFor(kind, b.method);
  const intervalDays = b.interval_days === undefined ? null : b.interval_days;
  if (intervalDays !== null && (!Number.isInteger(intervalDays) || intervalDays < 1 || intervalDays > 366)) throw C.httpError(400, "interval_days 1-366 arasında tamsayı olmalıdır.");
  const intervalMonths = b.interval_months === undefined ? 1 : b.interval_months;
  if (!Number.isInteger(intervalMonths) || intervalMonths < 1 || intervalMonths > 12) throw C.httpError(400, "interval_months 1-12 arasında tamsayı olmalıdır.");
  if (!isKurus(b.total_kurus)) throw C.httpError(400, "total_kurus kuruş tamsayısı olmalıdır.");
  if (!Number.isInteger(b.count) || b.count > MAX_BULK) throw C.httpError(400, `count 1-${MAX_BULK} arasında tamsayı olmalıdır.`);
  const plan = R.splitInstallments({ totalKurus: b.total_kurus, count: b.count, firstDue: first, intervalMonths, intervalDays });
  if (plan.error) throw C.httpError(400, plan.error);
  const groupId = require("crypto").randomUUID();
  const orgId = await orgIdForUser(ledger);
  const client = await db.pool.connect();
  let ids = [];
  try {
    await client.query("BEGIN");
    if (b.replace === true) {
      await client.query(`DELETE FROM payment_schedule WHERE owner_id = $1 AND status = 'bekliyor' AND kind = $2 AND ${l.project_id ? "project_id = $3" : "offer_id = $3"}`, [ledger, kind, l.project_id || l.offer_id]);
    }
    for (const it of plan.items) {
      const r = await client.query(
        `INSERT INTO payment_schedule (owner_id, org_id, created_by, project_id, offer_id, kind, amount_kurus, due_date, method, installment_no, group_id, note)
         VALUES ($1,$12,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
        [ledger, req.user.id, l.project_id || null, l.offer_id || null, kind, it.amount_kurus, it.due_date, method, it.seq, groupId, C.optText(b.note, "note", 1000) ?? null, orgId]);
      ids.push(r.rows[0].id);
    }
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
  const { rows } = await db.query(`SELECT ${COLS} ${FROM} WHERE s.id = ANY($1::uuid[]) ORDER BY s.installment_no`, [ids]);
  res.status(201).json({ group_id: groupId, total_kurus: b.total_kurus, items: rows.map((r) => serialize(r, C.today())) });
}));

router.get("/:id", C.guard, C.wrap(async (req, res) => res.json(serialize(await loadOne(req.params.id, await C.ledgerOf(req)), C.today()))));

router.patch("/:id", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req); const b = req.body || {};
  const row = await loadOne(req.params.id, ledger);
  const sets = {}; const l = await links(req, b, ledger);
  Object.assign(sets, l);
  if (b.kind !== undefined) sets.kind = C.oneOf(b.kind, KINDS, "kind");
  if (b.amount_kurus !== undefined) { if (!isKurus(b.amount_kurus) || b.amount_kurus < 1) throw C.httpError(400, "amount_kurus pozitif kuruş tamsayısı olmalıdır."); sets.amount_kurus = b.amount_kurus; }
  const due = C.optDate(b.due_date, "due_date"); if (due === null) throw C.httpError(400, "due_date boş olamaz."); if (due !== undefined) sets.due_date = due;
  if (b.method !== undefined || sets.kind !== undefined) sets.method = methodFor(sets.kind || row.kind, b.method === undefined ? row.method : b.method);
  for (const [k, max] of [["instrument_no", 64], ["bank", 100], ["note", 1000]]) { const v = C.optText(b[k], k, max); if (v !== undefined) sets[k] = v; }
  if (b.status !== undefined) {
    const st = C.oneOf(b.status, ["bekliyor", "iptal"], "status"); // 'odendi' yalnız mark-paid ile
    sets.status = st;
    if (st === "bekliyor") { sets.paid_at = null; sets.paid_payment_id = null; }
  }
  if (row.status === "odendi" && Object.keys(sets).some((k) => !["status", "note", "paid_at", "paid_payment_id"].includes(k))) throw C.httpError(409, "Ödenmiş plan satırı değiştirilemez; önce durumunu 'bekliyor' yapın.");
  const cols = Object.keys(sets);
  if (!cols.length) throw C.httpError(400, "Güncellenecek alan yok.");
  await db.query(`UPDATE payment_schedule SET ${cols.map((c, i) => `${c} = $${i + 1}`).join(", ")}, updated_at = now() WHERE id = $${cols.length + 1}`, [...cols.map((c) => sets[c]), row.id]);
  res.json(serialize(await loadOne(row.id, ledger), C.today()));
}));

router.delete("/:id", C.guard, C.wrap(async (req, res) => {
  const row = await loadOne(req.params.id, await C.ledgerOf(req));
  await db.query("DELETE FROM payment_schedule WHERE id = $1", [row.id]);
  res.json({ message: "Silindi." });
}));

/** Ödendi işaretle: {paid_at?, payment_id? (mevcut tahsilata bağla), create_payment? (payments'a TL olarak yaz), method?} */
router.post("/:id/mark-paid", C.guard, C.wrap(async (req, res) => {
  const ledger = await C.ledgerOf(req); const b = req.body || {};
  const row = await loadOne(req.params.id, ledger);
  if (row.status !== "bekliyor") throw C.httpError(409, row.status === "odendi" ? "Plan satırı zaten ödendi." : "İptal edilmiş plan satırı ödendi yapılamaz.");
  const paidAt = C.optDate(b.paid_at, "paid_at") || C.today();
  const paymentId = C.optUuid(b.payment_id, "payment_id");
  if (paymentId) await C.checkLink(req, "payment", paymentId, ledger);
  let projectId = row.project_id;
  if (b.create_payment === true) {
    if (paymentId) throw C.httpError(400, "create_payment ile payment_id birlikte verilemez.");
    if (!projectId && row.offer_id) projectId = (await db.query("SELECT id FROM projects WHERE offer_id = $1 ORDER BY start_date DESC LIMIT 1", [row.offer_id])).rows[0]?.id || null;
    if (!projectId) throw C.httpError(400, "Tahsilat kaydı için bir proje gerekir (plan satırı projeye bağlı değil).");
  }
  const method = b.method === undefined ? row.method || "Havale" : C.oneOf(b.method, METHODS, "method");
  const client = await db.pool.connect();
  let created = null;
  try {
    await client.query("BEGIN");
    let linkId = paymentId || null;
    if (b.create_payment === true) {
      const p = await client.query(
        "INSERT INTO payments (project_id, amount, method, note, paid_at, owner_id) VALUES ($1,$2,$3,$4,$5::timestamptz,$6) RETURNING id, amount",
        [projectId, fromKurus(row.amount_kurus), method, `Plan ödemesi${row.installment_no ? " #" + row.installment_no : ""}${row.instrument_no ? " (" + row.instrument_no + ")" : ""}`, `${paidAt}T12:00:00+03:00`, ledger]);
      created = p.rows[0]; linkId = created.id;
    }
    await client.query("UPDATE payment_schedule SET status = 'odendi', paid_at = $1, paid_payment_id = $2, method = COALESCE($3, method), updated_at = now() WHERE id = $4", [paidAt, linkId, method, row.id]);
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
  res.json({ ...serialize(await loadOne(row.id, ledger), C.today()), created_payment: created });
}));

module.exports = router;
