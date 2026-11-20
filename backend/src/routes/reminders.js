const express = require("express");
const db = require("../db");
const { requireAuth } = require("../middleware/auth");
const { canAccessResource } = require("../middleware/ownership");
const reminderSvc = require("../assistant/reminders/service");

const router = express.Router();

const isGlobal = (u) => u.role === "admin" || u.role === "muhasebe";

async function loadMine(req, res) {
  const { rows } = await db.query("SELECT * FROM reminders WHERE id = $1", [req.params.id]);
  if (!rows[0]) { res.status(404).json({ error: "Hatırlatıcı bulunamadı." }); return null; }
  if (!isGlobal(req.user) && String(rows[0].owner_id) !== String(req.user.id)) {
    res.status(403).json({ error: "Bu hatırlatıcı size ait değil." });
    return null;
  }
  return rows[0];
}

/** Hatırlatıcılar — admin/muhasebe hepsi; diğerleri yalnızca kendi oluşturdukları ya da erişebildikleri projeninkiler */
router.get("/", requireAuth, async (req, res) => {
  const { rows } = await db.query(`
    SELECT r.*, p.customer_name, p.service AS project_service, p.code AS project_code
    FROM reminders r
    LEFT JOIN projects p ON p.id = r.project_id
    WHERE ($2::boolean OR r.owner_id = $1
       OR (p.id IS NOT NULL AND (p.owner_id = $1 OR p.id IN (
            SELECT resource_id FROM resource_shares WHERE resource_type = 'project' AND shared_with_user_id = $1))))
    ORDER BY r.remind_at ASC
  `, [req.user.id, isGlobal(req.user)]);
  res.json(rows);
});

router.post("/", requireAuth, async (req, res) => {
  const { project_id, title, remind_at, note, recurrence } = req.body;
  if (!title || !remind_at) return res.status(400).json({ error: "Başlık ve tarih zorunludur." });
  if (Number.isNaN(new Date(remind_at).getTime())) return res.status(400).json({ error: "Geçersiz tarih." });
  if (!reminderSvc.validRecurrence(recurrence)) return res.status(400).json({ error: "recurrence daily | weekdays | weekly | monthly olmalı." });
  if (project_id) {
    const p = await db.query("SELECT owner_id FROM projects WHERE id = $1", [project_id]);
    if (!p.rows[0]) return res.status(404).json({ error: "Proje bulunamadı." });
    if (!(await canAccessResource(req.user, "project", project_id, p.rows[0].owner_id))) {
      return res.status(403).json({ error: "Bu projeye erişiminiz yok." });
    }
  }
  const { rows } = await db.query(
    "INSERT INTO reminders (project_id, title, remind_at, note, owner_id, recurrence) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *",
    [project_id || null, title, remind_at, note || null, req.user.id, recurrence || null]
  );
  await reminderSvc.schedule(rows[0]);
  res.status(201).json(rows[0]);
});

router.patch("/:id", requireAuth, async (req, res) => {
  const { status } = req.body;
  if (!["bekliyor", "tamamlandi"].includes(status)) return res.status(400).json({ error: "Geçersiz durum." });
  const mine = await loadMine(req, res);
  if (!mine) return;
  if (status === "tamamlandi" && mine.status === "bekliyor") return res.json((await reminderSvc.complete(mine)).reminder); // tekrarlıysa sonraki oluşum eklenir
  const { rows } = await db.query("UPDATE reminders SET status = $1 WHERE id = $2 RETURNING *", [status, req.params.id]);
  res.json(rows[0]);
});

router.delete("/:id", requireAuth, async (req, res) => {
  if (!(await loadMine(req, res))) return;
  await db.query("DELETE FROM reminders WHERE id = $1", [req.params.id]);
  res.json({ message: "Silindi." });
});

module.exports = router;
