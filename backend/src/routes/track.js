const express = require("express");
const db = require("../db");
const { createProjectFromOffer } = require("../services/offerProject");

const router = express.Router();

/**
 * PUBLIC — Müşterinin kendi teklifini takip kodu ile görüntülemesi.
 * Örn: GET /api/track/XCY-4F2A9
 * Kişisel/gizli veri (telefon, tam adres) döndürülmez — sadece durum ve teklif özeti.
 */
router.get("/:trackingCode", async (req, res) => {
  const { rows } = await db.query(
    "SELECT id, code, name, service, status, created_at FROM offers WHERE tracking_code = $1",
    [req.params.trackingCode]
  );
  const offer = rows[0];
  if (!offer) return res.status(404).json({ error: "Teklif bulunamadı." });

  const { rows: quoteRows } = await db.query(
    "SELECT items, subtotal, tax, total, created_at FROM quotes WHERE offer_id = $1 ORDER BY created_at DESC LIMIT 1",
    [offer.id]
  );

  res.json({ ...offer, quote: quoteRows[0] || null });
});

/**
 * PUBLIC — Müşterinin teklifi kabul/red etmesi.
 * body: { decision: "Kabul Edildi" | "Reddedildi" }
 */
router.post("/:trackingCode/decision", async (req, res) => {
  const { decision } = req.body;
  if (!["Kabul Edildi", "Reddedildi"].includes(decision)) {
    return res.status(400).json({ error: "Geçersiz karar." });
  }

  const { rows } = await db.query(
    "UPDATE offers SET status = $1, updated_at = now() WHERE tracking_code = $2 AND status = 'Teklif Verildi' RETURNING *",
    [decision, req.params.trackingCode]
  );
  if (!rows[0]) {
    return res.status(400).json({ error: "Bu teklif için karar verilemez (durum uygun değil)." });
  }

  if (decision === "Kabul Edildi") {
    // Panelden kabulle aynı akış: sahip, görevler ve paylaşımlar korunur, çift proje oluşmaz
    await createProjectFromOffer(rows[0].id);
  }

  res.json({ message: "Karar kaydedildi.", status: decision });
});

module.exports = router;
