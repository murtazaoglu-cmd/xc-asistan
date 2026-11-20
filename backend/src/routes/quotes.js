const express = require("express");
const { describeErrorForLog } = require("../services/logging");
const path = require("path");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const { generateQuotePDF } = require("../services/pdf");
const whatsapp = require("../services/whatsapp");
const email = require("../services/email");
const { canAccessResource } = require("../middleware/ownership");
const { signStored } = require("../services/fileAccess");

const router = express.Router();
const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, "../../uploads");

/**
 * Teklif toplamları — kuruş cinsinden tamsayı aritmetiği (float hatası ve yuvarlama kayması yok).
 * Her kalem kendi KDV durumunu taşır: vatIncluded=true → girilen fiyata %20 KDV dahildir (geriye doğru
 * ayrıştırılır); false → fiyat KDV hariçtir. Satır bazında yuvarlanır, total = subtotal + tax her zaman tutar.
 */
function computeTotals(items) {
  if (items.length > 200) { const err = new Error("Bir teklifte en çok 200 kalem olabilir."); err.status = 400; throw err; }
  let net = 0;    // kuruş
  let gross = 0;  // kuruş
  for (const it of items) {
    if (!it || typeof it !== "object" || (it.desc !== undefined && it.desc !== null && (typeof it.desc !== "string" || it.desc.length > 500))) {
      const err = new Error("Teklif kalemleri geçersiz (açıklama en çok 500 karakterlik metin olmalı).");
      err.status = 400;
      throw err;
    }
    const qty = Number(it.qty);
    const price = Number(it.price);
    if (!Number.isFinite(qty) || !Number.isFinite(price) || qty <= 0 || price < 0) {
      const err = new Error("Teklif kalemlerinde geçersiz adet veya fiyat var.");
      err.status = 400;
      throw err;
    }
    const line = Math.round(qty * price * 100);
    if (it.vatIncluded) {
      net += Math.round((line * 100) / 120);
      gross += line;
    } else {
      net += line;
      gross += line + Math.round(line * 0.2);
    }
  }
  return { subtotal: net / 100, tax: (gross - net) / 100, total: gross / 100 };
}

/** Teklifin sahibine/paylaşılan kişiye (veya admin/muhasebeye) erişim kontrolü */
async function checkOfferAccess(req, res, offerId) {
  const { rows } = await db.query("SELECT owner_id FROM offers WHERE id = $1", [offerId]);
  if (!rows[0]) { res.status(404).json({ error: "Teklif bulunamadı." }); return false; }
  if (!(await canAccessResource(req.user, "offer", offerId, rows[0].owner_id))) {
    res.status(403).json({ error: "Bu teklife erişiminiz yok." });
    return false;
  }
  return true;
}

/**
 * ADMIN — Teklif hazırla/güncelle. Kaydedilince teklifin durumu
 * otomatik "Teklif Verildi" olur.
 * body: { items: [{desc, qty, price}] }
 */
router.post("/:offerId", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  const { items } = req.body;
  if (!Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: "En az bir kalem gereklidir." });
  }
  if (!(await checkOfferAccess(req, res, req.params.offerId))) return;
  let totals;
  try { totals = computeTotals(items); } catch (e) { return res.status(e.status || 400).json({ error: e.message }); }
  const { subtotal, tax, total } = totals;

  const { rows } = await db.query(
    `INSERT INTO quotes (offer_id, items, subtotal, tax, total)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [req.params.offerId, JSON.stringify(items), subtotal, tax, total]
  );

  // Kabul/Red verilmiş bir teklifin durumunu geri düşürme
  await db.query(
    "UPDATE offers SET status = 'Teklif Verildi', updated_at = now() WHERE id = $1 AND status IN ('Yeni','İncelendi','Keşif Planlandı','Teklif Verildi')",
    [req.params.offerId]
  );

  res.status(201).json(rows[0]);
});

/**
 * ADMIN — Hazırlanan teklifi PDF olarak üretir, WhatsApp ve e-posta ile
 * OTOMATİK olarak müşteriye gönderir. Tek istekle her iki kanal da tetiklenir.
 */
router.post("/:offerId/send", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  try {
    if (!(await checkOfferAccess(req, res, req.params.offerId))) return;
    const { rows: offerRows } = await db.query("SELECT * FROM offers WHERE id = $1", [req.params.offerId]);
    const offer = offerRows[0];
    if (!offer) return res.status(404).json({ error: "Teklif bulunamadı." });

    const { rows: quoteRows } = await db.query(
      "SELECT * FROM quotes WHERE offer_id = $1 ORDER BY created_at DESC LIMIT 1",
      [req.params.offerId]
    );
    const quote = quoteRows[0];
    if (!quote) return res.status(400).json({ error: "Önce bir teklif hazırlanmalı." });

    // Teklif kalemleri veritabanında JSON string olarak tutulur
    const quoteForPdf = { ...quote, items: typeof quote.items === "string" ? JSON.parse(quote.items) : quote.items };

    const pdfPath = await generateQuotePDF(offer, quoteForPdf, UPLOAD_DIR);

    // Her kanalın GERÇEK sonucu: { sent, error } — sent:true yalnız sağlayıcı kabul ettiyse
    const channels = {
      whatsapp: { sent: false, error: null, skipped: false },
      email: { sent: false, error: null, skipped: false },
    };

    try {
      await whatsapp.sendDocument(
        offer.phone,
        pdfPath,
        `teklif-${offer.code}.pdf`,
        `${offer.name} için hazırladığımız teklif ektedir. Toplam: ${Number(quote.total).toLocaleString("tr-TR")} ₺`
      );
      channels.whatsapp.sent = true;
      await db.query("UPDATE quotes SET sent_via_whatsapp_at = now() WHERE id = $1", [quote.id]);
    } catch (err) {
      channels.whatsapp.error = whatsapp.describeError(err);
      console.error("Teklif WhatsApp gönderimi başarısız:", err.message);
    }

    if (offer.email) {
      try {
        await email.sendQuoteToCustomer(offer, quote, pdfPath);
        channels.email.sent = true;
        await db.query("UPDATE quotes SET sent_via_email_at = now() WHERE id = $1", [quote.id]);
      } catch (err) {
        channels.email.error = email.describeError(err);
        console.error("Teklif e-posta gönderimi başarısız:", err.message);
      }
    } else {
      channels.email.skipped = true;
      channels.email.error = "Müşterinin e-posta adresi yok.";
    }

    const okChannels = Object.keys(channels).filter((k) => channels[k].sent);
    const failed = Object.keys(channels).filter((k) => !channels[k].sent && !channels[k].skipped);
    const sent = okChannels.length > 0;
    // Durum: hiç gitmediyse basarisiz; gitmiş ama denenen bir kanal hata verdiyse kismen; hepsi gittiyse gonderildi
    const status = !sent ? "basarisiz" : failed.length > 0 ? "kismen" : "gonderildi";
    const errorText = failed.length ? failed.map((k) => `${k === "whatsapp" ? "WhatsApp" : "E-posta"}: ${channels[k].error}`).join(" | ")
      : (!sent ? channels.email.error : null);
    await db.query(
      "UPDATE quotes SET last_send_status = $1, last_send_at = now(), last_send_error = $2 WHERE id = $3",
      [status, errorText, quote.id]
    );

    // Panel/mobil için kısa ömürlü (10 dk) imzalı bağlantı. Müşteriye giden wa.me metnine İMZALI bağlantı konmaz (süresi dolar,
    // ve bağlantı üçüncü kişilere sızabilir): bunun yerine herkese açık teklif takip sayfası paylaşılır. Otomatik gönderimde PDF zaten ek olarak gider.
    const pdfUrl = signStored(`${process.env.APP_URL}/uploads/${path.basename(pdfPath)}`);
    const trackUrl = `${process.env.SITE_URL}/teklif-takip/${offer.tracking_code}`;
    // Eski istemciler için results (metin) korunur; yeni alanlar: sent, channel(s), error, status
    const legacy = (c) => (c.sent ? "gönderildi" : c.skipped ? "atlandı (e-posta yok)" : "hata: " + c.error);
    const body = {
      sent,
      channel: okChannels.length ? okChannels.join(",") : null,
      channels: {
        whatsapp: { sent: channels.whatsapp.sent, error: channels.whatsapp.error },
        email: { sent: channels.email.sent, skipped: channels.email.skipped, error: channels.email.error },
      },
      status,
      error: errorText,
      message: !sent ? "Teklif gönderilemedi." : status === "kismen" ? "Teklif kısmen gönderildi." : "Gönderim tamamlandı.",
      results: { whatsapp: legacy(channels.whatsapp), email: legacy(channels.email) },
      pdfUrl,
      // WhatsApp otomatik gönderimi başarısızsa kullanıcı kendi WhatsApp'ından gönderebilsin diye hazır bağlantı
      whatsappUrl: `https://wa.me/${whatsapp.normalizePhone(offer.phone)}?text=${encodeURIComponent(`Sayın ${offer.name}, teklifiniz: ${trackUrl}`)}`,
    };
    // Tamamen başarısız → 502 (istemci hata gösterir); kısmi → 207 (başarılı sayılır ama channels okunmalı); tam → 200
    res.status(!sent ? 502 : status === "kismen" ? 207 : 200).json(body);
  } catch (err) {
    console.error("POST /quotes/send hatası:", describeErrorForLog(err));
    res.status(500).json({ error: "Teklif gönderilemedi.", sent: false });
  }
});

module.exports = router;
