const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const { describeErrorForLog } = require("../services/logging");
const { financeOwnerId } = require("../middleware/access");
const { parseEmail } = require("../services/validate");
const { parseGeoFields, pushGeoSets, parseListParams, searchClause, queryList, sendList } = require("../services/helpers");

const router = express.Router();

/**
 * Müşteri listesi — telefon numarasına göre gruplanmış.
 * Hem tekliflerden türetilen müşterileri hem de elle eklenmiş (henüz teklifi olmayan)
 * müşterileri birleştirir.
 */
router.get("/", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  try {
    // "ortak" rolü sadece kendi owner_id'sine ait teklif/müşterileri görür (izole çalışma alanı).
    // admin/muhasebe için bu filtre devre dışı (ownerFilter = NULL).
    const ownerFilter = req.user.role === "ortak" ? req.user.id : null;
    const pg = parseListParams(req);
    const params = [ownerFilter, await financeOwnerId(req.user)]; // $2: çağıranın finans defteri (total_paid yalnız onu toplar — F-24)
    const base = `
    WITH offer_phone AS (
      SELECT id, regexp_replace(phone, '[^0-9]', '', 'g') AS phone_key
      FROM offers
      WHERE ($1::uuid IS NULL OR owner_id = $1)
    ),
    project_paid AS (
      SELECT project_id, COALESCE(SUM(amount),0) AS paid FROM payments
      WHERE owner_id = $2::uuid GROUP BY project_id
    ),
    projects_with_phone AS (
      SELECT pr.id, pr.total_amount, COALESCE(pp.paid,0) AS paid, op.phone_key
      FROM projects pr
      JOIN offer_phone op ON op.id = pr.offer_id
      LEFT JOIN project_paid pp ON pp.project_id = pr.id
    ),
    project_totals AS (
      SELECT phone_key, COUNT(*) AS project_count,
        COALESCE(SUM(total_amount),0) AS total_contracted,
        COALESCE(SUM(paid),0) AS total_paid
      FROM projects_with_phone GROUP BY phone_key
    ),
    offer_customers AS (
      SELECT op.phone_key,
        (array_agg(o.name ORDER BY o.created_at DESC))[1] AS name,
        (array_agg(o.email ORDER BY o.created_at DESC))[1] AS email,
        (array_agg(o.phone ORDER BY o.created_at DESC))[1] AS phone,
        (array_agg(o.region ORDER BY o.created_at DESC))[1] AS region,
        (array_agg(o.address ORDER BY o.created_at DESC) FILTER (WHERE o.address IS NOT NULL OR o.lat IS NOT NULL))[1] AS address,
        (array_agg(o.lat ORDER BY o.created_at DESC) FILTER (WHERE o.address IS NOT NULL OR o.lat IS NOT NULL))[1] AS lat,
        (array_agg(o.lng ORDER BY o.created_at DESC) FILTER (WHERE o.address IS NOT NULL OR o.lat IS NOT NULL))[1] AS lng,
        COUNT(*) AS offer_count,
        MIN(o.created_at) AS first_contact,
        MAX(o.created_at) AS last_contact
      FROM offers o JOIN offer_phone op ON op.id = o.id
      GROUP BY op.phone_key
    ),
    manual_customers AS (
      SELECT regexp_replace(phone, '[^0-9]', '', 'g') AS phone_key,
        name, email, phone, region, address, lat, lng, 0 AS offer_count, created_at AS first_contact, created_at AS last_contact
      FROM customers
      WHERE ($1::uuid IS NULL OR owner_id = $1)
    ),
    all_customers AS (
      SELECT * FROM offer_customers
      UNION ALL
      SELECT mc.phone_key, mc.name, mc.email, mc.phone, mc.region, mc.address, mc.lat, mc.lng, mc.offer_count, mc.first_contact, mc.last_contact
      FROM manual_customers mc
      WHERE NOT EXISTS (SELECT 1 FROM offer_customers oc WHERE oc.phone_key = mc.phone_key)
    )
    SELECT ac.phone_key, ac.name, ac.email, ac.phone, ac.region, ac.address, ac.lat, ac.lng,
      ac.offer_count, ac.first_contact, ac.last_contact,
      COALESCE(pt.project_count,0) AS project_count,
      COALESCE(pt.total_contracted,0) AS total_contracted,
      COALESCE(pt.total_paid,0) AS total_paid
    FROM all_customers ac
    LEFT JOIN project_totals pt ON pt.phone_key = ac.phone_key
    WHERE 1=1`;
    // ?q= arama: ad, telefon (rakam eşleşmesiyle de), e-posta, bölge, adres; ?limit/&offset sayfalama
    const sql = base + searchClause(pg, ["ac.name", "ac.email", "ac.region", "ac.address", "ac.phone"], "ac.phone", params);
    sendList(res, pg, await queryList(sql, params, "ORDER BY ac.last_contact DESC, ac.phone_key", pg));
  } catch (err) {
    console.error("GET /customers hatası:", describeErrorForLog(err));
    res.status(500).json({ error: "Müşteri listesi alınamadı." });
  }
});

/** Elle yeni müşteri ekle (henüz teklifi/projesi olmayan) */
router.post("/", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  const { name, phone, email, region, note } = req.body;
  if (!name || !phone) return res.status(400).json({ error: "Ad ve telefon zorunludur." });
  const em = parseEmail(email);
  if (em.error) return res.status(400).json({ error: "Geçerli bir e-posta adresi girin." });
  const geo = parseGeoFields(req.body);
  if (geo.error) return res.status(400).json({ error: geo.error });
  const g = geo.fields;
  const { rows } = await db.query(
    "INSERT INTO customers (name, phone, email, region, note, owner_id, address, lat, lng) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *",
    [name, phone, em.value, region || null, note || null, req.user.id, g.address ?? null, g.lat ?? null, g.lng ?? null]
  );
  res.status(201).json(rows[0]);
});

/** Tek müşterinin tam geçmişi (telefon anahtarına göre) */
router.get("/:phoneKey", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  const phoneKey = req.params.phoneKey;
  const ownerFilter = req.user.role === "ortak" ? req.user.id : null;

  const offersRes = await db.query(
    `SELECT * FROM offers WHERE regexp_replace(phone, '[^0-9]', '', 'g') = $1
       AND ($2::uuid IS NULL OR owner_id = $2) ORDER BY created_at DESC`,
    [phoneKey, ownerFilter]
  );
  const offerIds = offersRes.rows.map((o) => o.id);

  let projects = [];
  if (offerIds.length > 0) {
    const projectsRes = await db.query(
      // paid_amount: yalnız çağıranın defteri (F-24)
      `SELECT p.*, COALESCE((SELECT SUM(amount) FROM payments WHERE project_id = p.id AND owner_id = $2),0) AS paid_amount
       FROM projects p WHERE p.offer_id = ANY($1::uuid[]) ORDER BY p.start_date DESC`,
      [offerIds, await financeOwnerId(req.user)]
    );
    projects = projectsRes.rows;
  }

  res.json({ offers: offersRes.rows, projects });
});

/** Manuel eklenen müşteriyi düzenle (telefon numarasına göre eşleştirilir).
 *  Teklif üzerinden türetilen müşteriler için değil — onlar ilgili teklif düzenlenerek güncellenir. */
router.patch("/:phoneKey", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  const { name, email, region, note } = req.body;
  const geo = parseGeoFields(req.body);
  if (geo.error) return res.status(400).json({ error: geo.error });
  const em = email === undefined ? { value: undefined } : parseEmail(email);
  if (em.error) return res.status(400).json({ error: "Geçerli bir e-posta adresi girin." });
  const sets = []; const params = []; let i = 1;
  if (name !== undefined) { sets.push(`name = $${i++}`); params.push(name); }
  if (email !== undefined) { sets.push(`email = $${i++}`); params.push(em.value); }
  if (region !== undefined) { sets.push(`region = $${i++}`); params.push(region); }
  if (note !== undefined) { sets.push(`note = $${i++}`); params.push(note); }
  i = pushGeoSets(geo.fields, sets, params, i);
  if (sets.length === 0) return res.status(400).json({ error: "Güncellenecek alan yok." });

  const { rows } = await db.query(
    `UPDATE customers SET ${sets.join(", ")}
     WHERE regexp_replace(phone, '[^0-9]', '', 'g') = $${i} AND ($${i + 1}::uuid IS NULL OR owner_id = $${i + 1}) RETURNING *`,
    [...params, req.params.phoneKey, req.user.role === "ortak" ? req.user.id : null]
  );
  if (!rows[0]) return res.status(404).json({ error: "Bu müşteri manuel eklenmemiş, düzenlenemiyor (teklif üzerinden güncelleyin)." });
  res.json(rows[0]);
});

/** Manuel eklenen müşteriyi sil */
router.delete("/:phoneKey", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  await db.query(
    `DELETE FROM customers WHERE regexp_replace(phone, '[^0-9]', '', 'g') = $1 AND ($2::uuid IS NULL OR owner_id = $2)`,
    [req.params.phoneKey, req.user.role === "ortak" ? req.user.id : null]
  );
  res.json({ message: "Silindi." });
});

module.exports = router;
