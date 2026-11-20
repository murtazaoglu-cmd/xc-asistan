/** Açık alacak kalemlerinin VERİTABANI katmanı (saf mantık receivables.js'te). /api/receivables ve zamanlı hatırlatmalar kullanır. */
const db = require("../../db");
const R = require("./receivables");

/** Defterin açık alacakları: bekleyen plan satırları + vadeli açık giden faturalar (çift sayım yok) */
async function loadOpenItems(ledgerId, projectId = null) {
  const sched = (await db.query(
    `SELECT s.id, s.amount_kurus, s.due_date::text AS due_date, s.status, s.project_id, s.offer_id, s.invoice_id, s.kind, s.method,
            COALESCE(p.customer_name, o.name, i.counterparty) AS customer_name, p.code AS project_code
       FROM payment_schedule s LEFT JOIN projects p ON p.id = s.project_id LEFT JOIN offers o ON o.id = s.offer_id LEFT JOIN invoices i ON i.id = s.invoice_id
      WHERE s.owner_id = $1 AND s.status <> 'iptal' AND ($2::uuid IS NULL OR s.project_id = $2)`, [ledgerId, projectId])).rows;
  const invs = (await db.query(
    `SELECT i.id, i.odenecek_kurus, i.due_date::text AS due_date, i.status, i.direction, i.counterparty, i.project_id, i.invoice_no
       FROM invoices i WHERE i.owner_id = $1 AND i.direction = 'giden' AND i.status IN ('kesildi','gonderildi') AND i.due_date IS NOT NULL AND ($2::uuid IS NULL OR i.project_id = $2)`, [ledgerId, projectId])).rows;
  const meta = new Map([...sched.map((s) => [s.id, s.project_code]), ...invs.map((i) => [i.id, i.invoice_no])]);
  return R.openReceivables(sched, invs).map((it) => ({ ...it, ref: meta.get(it.id) || null }));
}

module.exports = { loadOpenItems };
