/**
 * /api/receivables — tahsilat yaşlandırma (0-30 / 31-60 / 61-90 / 90+) ve vadesi geçen listesi.
 * Kaynak: tahsilat planı (bekliyor) + vadeli açık GİDEN faturalar (faturaya bağlı taksit varsa fatura ayrıca sayılmaz → çift sayım yok).
 * Para: kuruş tamsayısı. Roller: admin/muhasebe/ortak (kendi defteri).
 */
const express = require("express");
const C = require("./common");
const { db } = C;
const R = require("../../assistant/tax/receivables");
const { loadOpenItems } = require("../../assistant/tax/receivablesService");

const router = express.Router();

async function gather(req) {
  const ledger = await C.ledgerOf(req);
  const today = C.optDate(req.query.asOf, "asOf") || C.today();
  let projectFilter = null;
  if (req.query.project_id !== undefined) { if (!C.isUuid(req.query.project_id)) throw C.httpError(400, "project_id geçersiz."); projectFilter = req.query.project_id; }
  return { today, items: await loadOpenItems(ledger, projectFilter) };
}

router.get("/aging", C.guard, C.wrap(async (req, res) => {
  const { today, items } = await gather(req);
  const a = R.buildAging(items, today);
  res.json({ ...a, sources: { plan: items.filter((i) => i.source === "plan").length, fatura: items.filter((i) => i.source === "fatura").length },
    note: "Faturaya bağlı taksit planı varsa fatura ayrıca sayılmaz. Vadesi olmayan faturalar yaşlandırılamaz." });
}));

router.get("/overdue", C.guard, C.wrap(async (req, res) => {
  const { today, items } = await gather(req);
  const min = req.query.min_days === undefined ? 1 : Number(req.query.min_days);
  if (!Number.isInteger(min) || min < 1 || min > 3650) throw C.httpError(400, "min_days 1-3650 arasında olmalıdır.");
  const a = R.buildAging(items, today);
  const list = a.overdueItems.filter((x) => x.days_overdue >= min);
  res.json({ asOf: today, count: list.length, totalKurus: list.reduce((s, x) => s + x.amount_kurus, 0), items: list });
}));

module.exports = router;
