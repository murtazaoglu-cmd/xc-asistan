const express = require("express");
const { requireAuth, requireRole } = require("../middleware/auth");
const settings = require("../assistant/settings");
const { orgIdForUser } = require("../assistant/org");
const { logAction } = require("../assistant/audit");

const router = express.Router();

/** GET /api/config — oturumu olan herkes: kuruluş markası, sektör sözlüğü, listeler, özellik bayrakları, sürüm bilgisi */
router.get("/", requireAuth, async (req, res) => {
  res.set("Cache-Control", "no-store");
  res.json(await settings.buildConfig(req.user));
});

/** PATCH /api/config — YALNIZ admin (şimdilik tek kuruluş). Kısmi güncelleme; liste alanları bütünüyle değişir, brand/terms birleştirilir. */
router.patch("/", requireAuth, requireRole("admin"), async (req, res) => {
  const v = settings.validatePatch(req.body);
  if (v.error) return res.status(400).json({ error: v.error });
  const orgId = await orgIdForUser(req.user.id);
  await settings.patchSettings(orgId, v.values);
  await logAction({ req, orgId, action: "config.update", entityType: "org", entityId: orgId, data: { fields: Object.keys(req.body) } });
  res.json(await settings.buildConfig(req.user));
});

module.exports = router;
