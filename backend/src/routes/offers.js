const express = require("express");
const { describeErrorForLog } = require("../services/logging");
const crypto = require("crypto");
const db = require("../db");
const { requireAuth, requireRole, optionalAuth } = require("../middleware/auth");
const { canAccessResource, scopeClause } = require("../middleware/ownership");
const { logActivity } = require("../middleware/activity");
const whatsapp = require("../services/whatsapp");
const email = require("../services/email");
const push = require("../services/push");
const { createProjectFromOffer } = require("../services/offerProject");
const { parseEmail, text, cleanPhotoUrls, normalizeSourceSite } = require("../services/validate");
const { parseGeoFields, pushGeoSets, parseListParams, searchClause, queryList, sendList } = require("../services/helpers");

const router = express.Router();

// Takip kodu tahmin edilemez olmalı (herkese açık /track uçları bu kodla veri döner): kriptografik rastgele, 8 karakter.
// (Eski 5 karakterlik kodlar geçerli kalır.)
function generateTrackingCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "XCY-";
  for (let i = 0; i < 8; i++) code += chars[crypto.randomInt(chars.length)];
  return code;
}

const MESSAGE_MAX = 2000;
const NOTES_MAX = 4000;
const bad = (res, msg) => res.status(400).json({ error: msg });

async function nextOfferCode() {
  // Veritabanı dizisi (schema_v14): eşzamanlı isteklerde bile çakışmaz.
  const { rows } = await db.query("SELECT 'OFR-' || nextval('offer_code_seq') AS code");
  return rows[0].code;
}

/**
 * PUBLIC (+ isteğe bağlı panel içi) — Web sitesindeki teklif formu ya da
 * panelden "Yeni Teklif" ile buraya POST atılır. Panel içinden, oturum açmış
 * bir kullanıcı tarafından oluşturulursa teklif o kullanıcıya (owner_id) atanır;
 * siteden anonim gelen teklifler sahipsiz (owner_id NULL) kalır — bunlar sadece
 * admin/muhasebe tarafından görülüp bir personele devredilebilir.
 */
router.post("/", optionalAuth, async (req, res) => {
  try {
    const { name, phone, email: customerEmail, service, region, message, photo_urls, source_site } = req.body;
    if (!name || !phone || !service) {
      return res.status(400).json({ error: "Ad, telefon ve hizmet türü zorunludur." });
    }
    if (typeof name !== "string" || typeof phone !== "string" || typeof service !== "string") {
      return bad(res, "Ad, telefon ve hizmet türü metin olmalıdır.");
    }
    // E-posta, nodemailer'a ulaşmadan ÖNCE burada doğrulanır (F-21); mesaj/bölge/kaynak sınırlanır (F-30)
    const em = parseEmail(customerEmail);
    if (em.error) return bad(res, "Geçerli bir e-posta adresi girin.");
    const msg = text(message, MESSAGE_MAX);
    if (msg.error) return bad(res, `Mesaj en çok ${MESSAGE_MAX} karakter olabilir.`);
    const reg = text(region, 200, { truncate: true });
    if (reg.error) return bad(res, "Bölge metin olmalıdır.");

    const geo = parseGeoFields(req.body);
    if (geo.error) return res.status(400).json({ error: geo.error });
    const g = geo.fields;

    const code = await nextOfferCode();
    const ownerId = req.user ? req.user.id : null;
    const photos = cleanPhotoUrls(photo_urls); // yalnız genel https adresleri (javascript:/dahili IP/localhost atılır)

    // Takip kodu çakışırsa (çok düşük ihtimal) yeniden dene
    let offer;
    for (let attempt = 0; attempt < 5 && !offer; attempt++) {
      try {
        const { rows } = await db.query(
          `INSERT INTO offers (code, tracking_code, name, phone, email, service, region, message, photo_urls, source, owner_id, source_site, address, lat, lng)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15) RETURNING *`,
          [code, generateTrackingCode(), String(name).slice(0, 200), String(phone).slice(0, 40), em.value,
           String(service).slice(0, 200), reg.value, msg.value, photos,
           req.user ? "admin" : "website", ownerId, normalizeSourceSite(source_site),
           g.address ?? null, g.lat ?? null, g.lng ?? null]
        );
        offer = rows[0];
      } catch (e) {
        if (e.code !== "23505" || !String(e.constraint || "").includes("tracking")) throw e;
      }
    }
    if (!offer) throw new Error("Takip kodu üretilemedi.");

    // Bildirimler — biri başarısız olsa da diğeri denenir, teklif kaybolmaz
    Promise.allSettled([
      whatsapp.notifyAdminNewOffer(offer),
      email.notifyAdminNewOffer(offer),
      push.notifyNewOffer(offer),
    ]).then((results) => {
      results.forEach((r) => { if (r.status === "rejected") console.error("Bildirim hatası:", r.reason?.message); });
    });

    res.status(201).json({
      message: "Teklif talebiniz alındı.",
      id: offer.id,
      code: offer.code,
      trackingCode: offer.tracking_code,
      trackingUrl: `${process.env.SITE_URL}/teklif-takip/${offer.tracking_code}`,
    });
  } catch (err) {
    console.error("POST /offers hatası:", describeErrorForLog(err));
    res.status(500).json({ error: "Teklif oluşturulamadı." });
  }
});

/**
 * Teklif listesi (filtre: ?status=Yeni). admin/muhasebe her şeyi görür;
 * diğer roller (örn. personel) sadece kendi oluşturduğu ya da kendisiyle
 * paylaşılan teklifleri görür.
 */
router.get("/", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const { status } = req.query;
  const pg = parseListParams(req);
  const params = [];
  let sql = `
    SELECT o.*, q.items AS quote_items, q.subtotal AS quote_subtotal,
           q.tax AS quote_tax, q.total AS quote_total, q.created_at AS quote_created_at,
           q.sent_via_whatsapp_at, q.sent_via_email_at,
           q.last_send_status, q.last_send_at, q.last_send_error
    FROM offers o
    LEFT JOIN LATERAL (
      SELECT * FROM quotes WHERE offer_id = o.id ORDER BY created_at DESC LIMIT 1
    ) q ON true
    WHERE 1=1
  `;
  if (status) {
    params.push(status);
    sql += ` AND o.status = $${params.length}`;
  }
  const scope = scopeClause(req.user, "o", "offer", params.length + 1);
  sql += ` ${scope.clause}`;
  params.push(...scope.params);
  // ?q= arama: ad, telefon (rakam eşleşmesiyle de), e-posta, kod, hizmet, bölge, adres
  sql += searchClause(pg, ["o.name", "o.email", "o.code", "o.service", "o.region", "o.address", "o.phone"], "o.phone", params);

  const result = await queryList(sql, params, "ORDER BY o.created_at DESC, o.id", pg);
  result.rows = result.rows.map((r) => ({
    ...r,
    quote: r.quote_total != null ? {
      items: r.quote_items, subtotal: r.quote_subtotal, tax: r.quote_tax, total: r.quote_total,
      created_at: r.quote_created_at, sent_via_whatsapp_at: r.sent_via_whatsapp_at, sent_via_email_at: r.sent_via_email_at,
      last_send_status: r.last_send_status, last_send_at: r.last_send_at, last_send_error: r.last_send_error,
    } : null,
  }));
  sendList(res, pg, result);
});

/** Tek teklif + varsa teklif kalemleri — sahiplik/paylaşım kontrolüyle */
router.get("/:id", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const { rows } = await db.query("SELECT * FROM offers WHERE id = $1", [req.params.id]);
  if (!rows[0]) return res.status(404).json({ error: "Teklif bulunamadı." });

  const allowed = await canAccessResource(req.user, "offer", req.params.id, rows[0].owner_id);
  if (!allowed) return res.status(403).json({ error: "Bu teklife erişiminiz yok." });

  const { rows: quotes } = await db.query(
    "SELECT * FROM quotes WHERE offer_id = $1 ORDER BY created_at DESC LIMIT 1",
    [req.params.id]
  );
  res.json({ ...rows[0], quote: quotes[0] || null });
});

/** Kabul Edildi → başka duruma geçiş yalnız admin'e açık; aynı durumu yeniden göndermek zararsızdır */
function mayChangeStatus(user, from, to) {
  return !(from === "Kabul Edildi" && to !== "Kabul Edildi" && user.role !== "admin");
}

/** Durum güncelle (Yeni, İncelendi, Keşif Planlandı, Teklif Verildi, Kabul Edildi, Reddedildi) */
router.patch("/:id/status", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const { status } = req.body;
  const valid = ["Yeni", "İncelendi", "Keşif Planlandı", "Teklif Verildi", "Kabul Edildi", "Reddedildi"];
  if (!valid.includes(status)) return res.status(400).json({ error: "Geçersiz durum." });

  const existing = await db.query("SELECT owner_id, status FROM offers WHERE id = $1", [req.params.id]);
  if (!existing.rows[0]) return res.status(404).json({ error: "Teklif bulunamadı." });
  const allowed = await canAccessResource(req.user, "offer", req.params.id, existing.rows[0].owner_id);
  if (!allowed) return res.status(403).json({ error: "Bu teklife erişiminiz yok." });
  // Kabul edilmiş teklif (proje oluşmuş) yalnız admin tarafından geri alınabilir (F-29)
  if (!mayChangeStatus(req.user, existing.rows[0].status, status)) {
    return res.status(409).json({ error: "Kabul edilmiş teklifin durumu değiştirilemez (yalnızca yönetici düzeltebilir)." });
  }

  const { rows } = await db.query(
    "UPDATE offers SET status = $1, updated_at = now() WHERE id = $2 RETURNING *",
    [status, req.params.id]
  );
  logActivity("offer", req.params.id, req.user.id, "durum_degisti", status);

  // Kabul edildiyse otomatik proje oluştur — sahiplik teklifle birlikte devrolur
  if (status === "Kabul Edildi") {
    await createProjectFromOffer(rows[0].id);
  }

  res.json(rows[0]);
});

/** Toplu durum değiştirme — birden fazla teklifi tek seferde güncelle */
router.patch("/bulk-status", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const { ids, status } = req.body;
  const valid = ["Yeni", "İncelendi", "Keşif Planlandı", "Teklif Verildi", "Kabul Edildi", "Reddedildi"];
  if (!Array.isArray(ids) || ids.length === 0 || !valid.includes(status)) {
    return res.status(400).json({ error: "Geçerli id listesi ve durum zorunludur." });
  }
  let updated = 0;
  for (const id of ids) {
    const existing = await db.query("SELECT owner_id, status FROM offers WHERE id = $1", [id]);
    if (!existing.rows[0]) continue;
    const allowed = await canAccessResource(req.user, "offer", id, existing.rows[0].owner_id);
    if (!allowed) continue;
    if (!mayChangeStatus(req.user, existing.rows[0].status, status)) continue;
    await db.query("UPDATE offers SET status = $1, updated_at = now() WHERE id = $2", [status, id]);
    if (status === "Kabul Edildi") await createProjectFromOffer(id);
    logActivity("offer", id, req.user.id, "durum_degisti", status + " (toplu)");
    updated++;
  }
  res.json({ message: `${updated} teklif güncellendi.`, updated });
});

/** Toplu silme — birden fazla teklifi tek seferde sil (sadece erişim yetkisi olanlar silinir) */
router.delete("/bulk", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  // admin her teklifi silebilir; diğer roller yalnızca KENDİ oluşturdukları teklifleri (paylaşılanları değil)
  const { ids } = req.body;
  if (!Array.isArray(ids) || ids.length === 0) {
    return res.status(400).json({ error: "Geçerli id listesi zorunludur." });
  }
  let deleted = 0;
  for (const id of ids) {
    const existing = await db.query("SELECT owner_id FROM offers WHERE id = $1", [id]);
    if (!existing.rows[0]) continue;
    const mayDelete = req.user.role === "admin" || String(existing.rows[0].owner_id) === String(req.user.id);
    if (!mayDelete) continue;
    await db.query("UPDATE projects SET offer_id = NULL WHERE offer_id = $1", [id]);
    await db.query("DELETE FROM offers WHERE id = $1", [id]);
    deleted++;
  }
  res.json({ message: `${deleted} teklif silindi.`, deleted });
});

/** Teklifin temel bilgilerini düzenle (ad, telefon, e-posta, hizmet, bölge, not, adres, lat/lng) */
router.patch("/:id", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const existing = await db.query("SELECT owner_id FROM offers WHERE id = $1", [req.params.id]);
  if (!existing.rows[0]) return res.status(404).json({ error: "Teklif bulunamadı." });
  const allowed = await canAccessResource(req.user, "offer", req.params.id, existing.rows[0].owner_id);
  if (!allowed) return res.status(403).json({ error: "Bu teklife erişiminiz yok." });

  const { name, phone, email, service, region, message, notes } = req.body;
  const geo = parseGeoFields(req.body);
  if (geo.error) return res.status(400).json({ error: geo.error });
  // Alan doğrulama (tip + uzunluk) — e-posta nodemailer'a gideceğinden biçimi sıkı denetlenir (F-21/F-30)
  const em = email === undefined ? { value: undefined } : parseEmail(email);
  if (em.error) return bad(res, "Geçerli bir e-posta adresi girin.");
  for (const [k, v, max] of [["name", name, 200], ["phone", phone, 40], ["service", service, 200], ["region", region, 200], ["message", message, MESSAGE_MAX], ["notes", notes, NOTES_MAX]]) {
    if (v === undefined || v === null) continue;
    if (typeof v !== "string") return bad(res, `${k} metin olmalıdır.`);
    if (v.length > max) return bad(res, `${k} en çok ${max} karakter olabilir.`);
  }
  const sets = []; const params = []; let i = 1;
  if (name !== undefined) { sets.push(`name = $${i++}`); params.push(name); }
  if (phone !== undefined) { sets.push(`phone = $${i++}`); params.push(phone); }
  if (email !== undefined) { sets.push(`email = $${i++}`); params.push(em.value); }
  if (service !== undefined) { sets.push(`service = $${i++}`); params.push(service); }
  if (region !== undefined) { sets.push(`region = $${i++}`); params.push(region); }
  if (message !== undefined) { sets.push(`message = $${i++}`); params.push(message); }
  if (notes !== undefined) { sets.push(`notes = $${i++}`); params.push(notes); }
  i = pushGeoSets(geo.fields, sets, params, i);
  if (sets.length === 0) return res.status(400).json({ error: "Güncellenecek alan yok." });
  sets.push(`updated_at = now()`);
  params.push(req.params.id);

  const { rows } = await db.query(`UPDATE offers SET ${sets.join(", ")} WHERE id = $${i} RETURNING *`, params);
  logActivity("offer", req.params.id, req.user.id, "duzenlendi", null);
  res.json(rows[0]);
});

/** Teklifi sil (sadece yönetici — geri alınamaz). Bu teklifin bağlı olduğu bir proje
 *  varsa proje SİLİNMEZ, sadece teklif bağlantısı kaldırılır (proje bağımsız yaşar). */
router.delete("/:id", requireAuth, requireRole("admin","ortak","personel"), async (req, res) => {
  const id = req.params.id;
  const existing = await db.query("SELECT owner_id FROM offers WHERE id = $1", [id]);
  if (!existing.rows[0]) return res.status(404).json({ error: "Teklif bulunamadı." });
  if (req.user.role !== "admin" && String(existing.rows[0].owner_id) !== String(req.user.id)) {
    return res.status(403).json({ error: "Yalnızca kendi oluşturduğunuz teklifi silebilirsiniz." });
  }
  await db.query("UPDATE projects SET offer_id = NULL WHERE offer_id = $1", [id]);
  await db.query("DELETE FROM appointments WHERE offer_id = $1", [id]);
  await db.query("DELETE FROM whatsapp_messages WHERE offer_id = $1", [id]);
  await db.query("DELETE FROM offers WHERE id = $1", [id]);
  res.json({ message: "Teklif silindi." });
});

module.exports = router;
