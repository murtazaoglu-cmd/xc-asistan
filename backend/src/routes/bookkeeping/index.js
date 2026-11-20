/**
 * v18 — Fatura takibi, KDV, vergi takvimi, tahsilat planı, WhatsApp şablonları. server.js tek satırla bağlar:
 *   app.use("/api", require("./routes/bookkeeping"));
 * Uçlar: /api/invoices, /api/vat, /api/tax-calendar, /api/payment-schedule, /api/receivables, /api/message-templates
 */
const express = require("express");
const router = express.Router();

router.use("/invoices", require("./invoices"));
router.use("/vat", require("./vat"));
router.use("/tax-calendar", require("./taxCalendar"));
router.use("/payment-schedule", require("./paymentSchedule"));
router.use("/receivables", require("./receivables"));
router.use("/message-templates", require("./messageTemplates"));

module.exports = router;
