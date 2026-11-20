const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const prefsSvc = require("../assistant/prefs");
const planner = require("../assistant/planner");
const settings = require("../assistant/settings");
const { notifyUser } = require("../assistant/notify");
const { orgIdForUser } = require("../assistant/org");
const { logAction } = require("../assistant/audit");
const fcm = require("../assistant/fcmv1");
const clock = require("../assistant/clock");

const router = express.Router();

// ---- bildirim tercihleri -------------------------------------------------------------------------
router.get("/prefs", requireAuth, async (req, res) => res.json(await prefsSvc.getPrefs(req.user.id)));

/** PUT /prefs — upsert; yalnız gönderilen alanlar değişir. Saat değişince bugünün bekleyen brifing/kapanış işleri yeniden zamanlanır. */
router.put("/prefs", requireAuth, async (req, res) => {
  const v = prefsSvc.validate(req.body);
  if (v.error) return res.status(400).json({ error: v.error });
  if (Object.keys(v.values).length === 0) return res.status(400).json({ error: "Değiştirilecek alan yok." });
  const p = await prefsSvc.savePrefs(req.user.id, v.values);
  await planner.planUser(req.user.id).catch((e) => console.error("planUser hatası:", e.message));
  res.json(p);
});

// ---- sektör şablonları ---------------------------------------------------------------------------
router.get("/sector-templates", requireAuth, async (req, res) => res.json(await settings.listTemplates()));

/** POST /sector-templates/apply {key, mode?: "replace"|"merge"} — YALNIZ admin; yalnız ayarlar değişir, mevcut kayıtlar silinmez */
router.post("/sector-templates/apply", requireAuth, requireRole("admin"), async (req, res) => {
  const { key, mode } = req.body || {};
  if (typeof key !== "string" || !key || key.length > 60) return res.status(400).json({ error: "Şablon anahtarı (key) gerekli." });
  if (mode !== undefined && !["replace", "merge"].includes(mode)) return res.status(400).json({ error: "mode replace veya merge olmalı." });
  const orgId = await orgIdForUser(req.user.id);
  const tpl = await settings.applyTemplate(orgId, key, mode || "replace");
  if (!tpl) return res.status(404).json({ error: "Şablon bulunamadı." });
  await logAction({ req, orgId, action: "sector_template.apply", entityType: "org", entityId: orgId, data: { key, mode: mode || "replace" } });
  res.json({ applied: tpl.key, config: await settings.buildConfig(req.user) });
});

// ---- uygulama içi bildirim kutusu (FCM kapalıyken de çalışır; yerel bildirim yedeği) ---------------------
const itemCols = "id, type, title, body, data, priority, status, not_before AS available_at, created_at, read_at, acked_at";
const visible = "user_id = $1 AND status <> 'iptal' AND not_before <= $2";

/** GET /inbox?unread=1&limit=30&before=<available_at ISO> → {items, unread_count, next_before} */
router.get("/inbox", requireAuth, async (req, res) => {
  const now = clock.now();
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 30, 1), 100);
  const params = [req.user.id, now];
  let extra = "";
  if (req.query.unread === "1" || req.query.unread === "true") extra += " AND read_at IS NULL";
  if (req.query.before) {
    const b = new Date(req.query.before);
    if (Number.isNaN(b.getTime())) return res.status(400).json({ error: "Geçersiz before." });
    params.push(b); extra += ` AND not_before < $${params.length}`;
  }
  params.push(limit + 1);
  const [list, cnt] = await Promise.all([
    db.query(`SELECT ${itemCols} FROM notification_outbox WHERE ${visible}${extra} ORDER BY not_before DESC, id DESC LIMIT $${params.length}`, params),
    db.query(`SELECT COUNT(*)::int AS n FROM notification_outbox WHERE ${visible} AND read_at IS NULL`, [req.user.id, now]),
  ]);
  const items = list.rows.slice(0, limit);
  res.json({ items, unread_count: cnt.rows[0].n, next_before: list.rows.length > limit ? items[items.length - 1].available_at : null });
});

async function mark(req, res, sql) {
  const r = await db.query(sql, [req.params.id, req.user.id]);
  if (!r.rows[0]) return res.status(404).json({ error: "Bildirim bulunamadı." });
  res.json(r.rows[0]);
}
router.post("/inbox/read-all", requireAuth, async (req, res) => {
  const r = await db.query(`UPDATE notification_outbox SET read_at = now() WHERE user_id = $1 AND read_at IS NULL AND status <> 'iptal' AND not_before <= $2`, [req.user.id, clock.now()]);
  res.json({ marked: r.rowCount });
});
router.post("/inbox/:id/read", requireAuth, (req, res) => mark(req, res,
  `UPDATE notification_outbox SET read_at = COALESCE(read_at, now()) WHERE id = $1 AND user_id = $2 AND status <> 'iptal' RETURNING ${itemCols}`));
router.post("/inbox/:id/unread", requireAuth, (req, res) => mark(req, res,
  `UPDATE notification_outbox SET read_at = NULL WHERE id = $1 AND user_id = $2 AND status <> 'iptal' RETURNING ${itemCols}`));
/** Ack: istemci bildirimi aldı/açtı (idempotent; okundu da sayılır) */
router.post("/inbox/:id/ack", requireAuth, (req, res) => mark(req, res,
  `UPDATE notification_outbox SET acked_at = COALESCE(acked_at, now()), read_at = COALESCE(read_at, now()) WHERE id = $1 AND user_id = $2 AND status <> 'iptal' RETURNING ${itemCols}`));

/** POST /test-notification — kendine test bildirimi (dakikada en çok 1; FCM kapalıysa yalnız kutuya düşer) */
router.post("/test-notification", requireAuth, async (req, res) => {
  const bucket = Math.floor(Date.now() / 60000);
  const r = await notifyUser(req.user.id, { type: "test", title: "Test bildirimi", body: "Bildirimler çalışıyor.", dedupeKey: `test:${req.user.id}:${bucket}`, sendAt: clock.now() });
  res.status(r.deduped ? 200 : 201).json({ id: r.id, deduped: r.deduped, fcm_enabled: fcm.isEnabled() });
});

module.exports = router;
