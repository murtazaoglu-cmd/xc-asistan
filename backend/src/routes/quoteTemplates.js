const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");

const router = express.Router();

router.get("/", requireAuth, requireRole("admin", "muhasebe"), async (req, res) => {
  const { rows } = await db.query("SELECT * FROM quote_templates ORDER BY created_at DESC");
  res.json(rows);
});

router.post("/", requireAuth, requireRole("admin", "muhasebe"), async (req, res) => {
  const { name, items } = req.body;
  if (!name || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: "Şablon adı ve en az bir kalem zorunludur." });
  }
  const { rows } = await db.query(
    "INSERT INTO quote_templates (name, items) VALUES ($1,$2) RETURNING *",
    [name, JSON.stringify(items)]
  );
  res.status(201).json(rows[0]);
});

router.delete("/:id", requireAuth, requireRole("admin", "muhasebe"), async (req, res) => {
  await db.query("DELETE FROM quote_templates WHERE id = $1", [req.params.id]);
  res.json({ message: "Silindi." });
});

module.exports = router;
