const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");

const router = express.Router();

/** "Ortak" rolü sadece kendi stoğunu görür/yönetir; admin/muhasebe için kısıtlama yok. */
router.get("/", requireAuth, requireRole("admin", "muhasebe", "ortak"), async (req, res) => {
  const ownerFilter = req.user.role === "ortak" ? req.user.id : null;
  const { rows } = await db.query(
    "SELECT * FROM materials WHERE ($1::uuid IS NULL OR owner_id = $1) ORDER BY name ASC",
    [ownerFilter]
  );
  res.json(rows);
});

router.post("/", requireAuth, requireRole("admin", "muhasebe", "ortak"), async (req, res) => {
  const { name, unit, stock_quantity, low_stock_threshold, note } = req.body;
  if (!name) return res.status(400).json({ error: "Malzeme adı zorunludur." });
  for (const v of [stock_quantity, low_stock_threshold]) {
    if (v !== undefined && v !== null && v !== "" && (!Number.isFinite(Number(v)) || Number(v) < 0)) {
      return res.status(400).json({ error: "Stok değerleri geçerli ve negatif olmayan sayılar olmalıdır." });
    }
  }
  const { rows } = await db.query(
    `INSERT INTO materials (name, unit, stock_quantity, low_stock_threshold, note, owner_id)
     VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
    [name, unit || "adet", stock_quantity || 0, low_stock_threshold || 5, note || null, req.user.id]
  );
  res.status(201).json(rows[0]);
});

router.patch("/:id", requireAuth, requireRole("admin", "muhasebe", "ortak"), async (req, res) => {
  if (req.user.role === "ortak") {
    const existing = await db.query("SELECT owner_id FROM materials WHERE id = $1", [req.params.id]);
    if (!existing.rows[0]) return res.status(404).json({ error: "Malzeme bulunamadı." });
    if (String(existing.rows[0].owner_id) !== String(req.user.id)) {
      return res.status(403).json({ error: "Bu malzeme size ait değil." });
    }
  }
  const { name, unit, stock_quantity, low_stock_threshold, note } = req.body;
  const sets = []; const params = []; let i = 1;
  if (name !== undefined) { sets.push(`name = $${i++}`); params.push(name); }
  if (unit !== undefined) { sets.push(`unit = $${i++}`); params.push(unit); }
  if (stock_quantity !== undefined) { sets.push(`stock_quantity = $${i++}`); params.push(stock_quantity); }
  if (low_stock_threshold !== undefined) { sets.push(`low_stock_threshold = $${i++}`); params.push(low_stock_threshold); }
  if (note !== undefined) { sets.push(`note = $${i++}`); params.push(note); }
  sets.push(`updated_at = now()`);
  if (sets.length === 1) return res.status(400).json({ error: "Güncellenecek alan yok." });
  params.push(req.params.id);
  const { rows } = await db.query(`UPDATE materials SET ${sets.join(", ")} WHERE id = $${i} RETURNING *`, params);
  if (!rows[0]) return res.status(404).json({ error: "Malzeme bulunamadı." });
  res.json(rows[0]);
});

router.delete("/:id", requireAuth, requireRole("admin", "muhasebe", "ortak"), async (req, res) => {
  if (req.user.role === "ortak") {
    const existing = await db.query("SELECT owner_id FROM materials WHERE id = $1", [req.params.id]);
    if (!existing.rows[0]) return res.status(404).json({ error: "Malzeme bulunamadı." });
    if (String(existing.rows[0].owner_id) !== String(req.user.id)) {
      return res.status(403).json({ error: "Bu malzeme size ait değil." });
    }
  }
  await db.query("DELETE FROM materials WHERE id = $1", [req.params.id]);
  res.json({ message: "Silindi." });
});

module.exports = router;
