const express = require("express");
const db = require("../db");
const { requireAuth } = require("../middleware/auth");
const { canAccessResource } = require("../middleware/ownership");

const router = express.Router();

router.get("/:resourceType/:resourceId", requireAuth, async (req, res) => {
  const { resourceType, resourceId } = req.params;
  if (!["offer", "project"].includes(resourceType)) return res.status(400).json({ error: "Geçersiz kaynak türü." });

  const table = resourceType === "offer" ? "offers" : "projects";
  const ownerRes = await db.query(`SELECT owner_id FROM ${table} WHERE id = $1`, [resourceId]);
  const ownerId = ownerRes.rows[0]?.owner_id;
  const allowed = await canAccessResource(req.user, resourceType, resourceId, ownerId);
  if (!allowed) return res.status(403).json({ error: "Bu kayda erişiminiz yok." });

  const { rows } = await db.query(`
    SELECT a.*, u.name AS user_name
    FROM activity_log a LEFT JOIN users u ON u.id = a.user_id
    WHERE a.resource_type = $1 AND a.resource_id = $2
    ORDER BY a.created_at DESC LIMIT 100
  `, [resourceType, resourceId]);
  res.json(rows);
});

module.exports = router;
