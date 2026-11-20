const express = require("express");
const db = require("../db");
const { requireAuth } = require("../middleware/auth");
const { canAccessResource } = require("../middleware/ownership");
const { logActivity } = require("../middleware/activity");
const push = require("../services/push");

const router = express.Router();

/** Bir kaynağın (teklif/proje) kimlerle paylaşıldığını listele */
router.get("/:resourceType/:resourceId", requireAuth, async (req, res) => {
  const { resourceType, resourceId } = req.params;
  if (!["offer", "project"].includes(resourceType)) return res.status(400).json({ error: "Geçersiz kaynak türü." });

  const table = resourceType === "offer" ? "offers" : "projects";
  const ownerRes = await db.query(`SELECT owner_id FROM ${table} WHERE id = $1`, [resourceId]);
  const ownerId = ownerRes.rows[0]?.owner_id;

  const allowed = await canAccessResource(req.user, resourceType, resourceId, ownerId);
  if (!allowed) return res.status(403).json({ error: "Bu kayda erişiminiz yok." });

  const { rows } = await db.query(`
    SELECT rs.*, u.name AS user_name, u.email AS user_email
    FROM resource_shares rs JOIN users u ON u.id = rs.shared_with_user_id
    WHERE rs.resource_type = $1 AND rs.resource_id = $2
  `, [resourceType, resourceId]);
  res.json(rows);
});

/** Bir kaynağı (teklif/proje) başka bir kullanıcıyla paylaş */
router.post("/", requireAuth, async (req, res) => {
  const { resource_type, resource_id, user_id } = req.body;
  if (!["offer", "project"].includes(resource_type) || !resource_id || !user_id) {
    return res.status(400).json({ error: "resource_type, resource_id ve user_id zorunludur." });
  }

  const table = resource_type === "offer" ? "offers" : "projects";
  const ownerRes = await db.query(`SELECT owner_id FROM ${table} WHERE id = $1`, [resource_id]);
  if (!ownerRes.rows[0]) return res.status(404).json({ error: "Kayıt bulunamadı." });
  const ownerId = ownerRes.rows[0].owner_id;

  // Paylaşımı yalnızca kaydın sahibi ya da admin/muhasebe yapabilir (paylaşılan kişi yeniden paylaşamaz)
  const isOwnerOrStaff = req.user.role === "admin" || req.user.role === "muhasebe" || String(ownerId) === String(req.user.id);
  if (!isOwnerOrStaff) return res.status(403).json({ error: "Bu kaydı paylaşma yetkiniz yok." });

  // Hedef kullanıcı var olmalı; ortak yalnızca kendi ekibiyle (oluşturduğu kullanıcılarla) paylaşabilir
  const target = await db.query("SELECT id, created_by FROM users WHERE id = $1", [user_id]);
  if (!target.rows[0]) return res.status(404).json({ error: "Kullanıcı bulunamadı." });
  if (req.user.role === "ortak" && String(target.rows[0].created_by) !== String(req.user.id)) {
    return res.status(403).json({ error: "Yalnızca kendi ekibinizdeki kullanıcılarla paylaşabilirsiniz." });
  }
  if (String(user_id) === String(ownerId)) return res.status(400).json({ error: "Kayıt zaten bu kullanıcıya ait." });

  const nameField = resource_type === "offer" ? "name" : "customer_name";
  const nameRes = await db.query(`SELECT ${nameField} AS name FROM ${table} WHERE id = $1`, [resource_id]);
  const resourceName = nameRes.rows[0]?.name || "";

  const { rows } = await db.query(`
    INSERT INTO resource_shares (resource_type, resource_id, shared_with_user_id, shared_by_user_id)
    VALUES ($1,$2,$3,$4)
    ON CONFLICT (resource_type, resource_id, shared_with_user_id) DO NOTHING
    RETURNING *
  `, [resource_type, resource_id, user_id, req.user.id]);

  if (rows[0]) {
    logActivity(resource_type, resource_id, req.user.id, "paylasildi", `→ kullanıcı ${user_id}`);
    push.notifyUser(
      user_id,
      "Sizinle bir kayıt paylaşıldı",
      `${req.user.name || "Bir kullanıcı"}, "${resourceName}" ${resource_type === "offer" ? "teklifini" : "projesini"} sizinle paylaştı.`,
      "/"
    );
  }
  res.status(201).json(rows[0] || { message: "Zaten paylaşılmış." });
});

/** Paylaşımı kaldır */
router.delete("/:id", requireAuth, async (req, res) => {
  const share = await db.query("SELECT * FROM resource_shares WHERE id = $1", [req.params.id]);
  if (!share.rows[0]) return res.status(404).json({ error: "Paylaşım bulunamadı." });
  const sh = share.rows[0];
  const table = sh.resource_type === "offer" ? "offers" : "projects";
  const ownerRes = await db.query(`SELECT owner_id FROM ${table} WHERE id = $1`, [sh.resource_id]);
  const allowed = req.user.role === "admin" || req.user.role === "muhasebe"
    || String(ownerRes.rows[0]?.owner_id) === String(req.user.id)
    || String(sh.shared_by_user_id) === String(req.user.id);
  if (!allowed) return res.status(403).json({ error: "Bu paylaşımı kaldırma yetkiniz yok." });
  await db.query("DELETE FROM resource_shares WHERE id = $1", [req.params.id]);
  res.json({ message: "Paylaşım kaldırıldı." });
});

module.exports = router;
