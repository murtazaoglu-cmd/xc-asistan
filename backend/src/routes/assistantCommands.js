const express = require("express");
const { requireAuth } = require("../middleware/auth");
const svc = require("../assistant/command/service");

/**
 * Komut çubuğu uçları (v19) — /api/assistant altında (routes/assistant.js ile aynı önek).
 *   POST /commands {text, choices?}              → {kind:"answer"|"action_card"|"clarify", …}
 *   GET  /commands/chips                         → hazır sorgu çipleri
 *   GET  /actions[?status=&limit=]  ·  GET /actions/:id
 *   PATCH /actions/:id {fields}                  → kartı düzenle
 *   POST /actions/:id/confirm {fields?} | /reject | /undo
 * Yazma YALNIZ confirm ile ve mevcut REST uçları üzerinden (aynı yetki) uygulanır.
 */
const router = express.Router();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const idOr400 = (req, res) => { if (UUID.test(req.params.id)) return true; res.status(400).json({ error: "Geçersiz kimlik." }); return false; };

function wrap(fn) {
  return async (req, res) => {
    try { await fn(req, res); }
    catch (err) {
      if (err && err.expose && err.status) return res.status(err.status).json({ error: err.message, ...(err.extra || {}) });
      throw err;
    }
  };
}

router.post("/commands", requireAuth, wrap(async (req, res) => {
  const out = await svc.handleCommand(req, (req.body || {}).text, (req.body || {}).choices);
  res.status(out.kind === "action_card" && !out.deduped ? 201 : 200).json(out);
}));

router.get("/commands/chips", requireAuth, (req, res) => res.json({ chips: svc.chipsFor(req.user.role) }));

router.get("/actions", requireAuth, wrap(async (req, res) => res.json({ items: await svc.listActions(req.user, req.query) })));
router.get("/actions/:id", requireAuth, wrap(async (req, res) => { if (idOr400(req, res)) res.json(await svc.getAction(req.user, req.params.id)); }));
router.patch("/actions/:id", requireAuth, wrap(async (req, res) => { if (idOr400(req, res)) res.json(await svc.editAction(req, req.params.id, (req.body || {}).fields)); }));
router.post("/actions/:id/confirm", requireAuth, wrap(async (req, res) => {
  if (!idOr400(req, res)) return;
  const out = await svc.confirmAction(req, req.params.id, (req.body || {}).fields);
  res.status(200).json({ ...out.action, replayed: out.replayed });
}));
router.post("/actions/:id/reject", requireAuth, wrap(async (req, res) => { if (idOr400(req, res)) res.json(await svc.rejectAction(req, req.params.id)); }));
router.post("/actions/:id/undo", requireAuth, wrap(async (req, res) => { if (idOr400(req, res)) res.json(await svc.undoAction(req, req.params.id)); }));

module.exports = router;
