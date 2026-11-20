const db = require("../db");
const { defaultOrgId } = require("./org");

/**
 * Denetim izi. Asla istisna fırlatmaz (iş akışını bozmaz), başarıyı döner.
 *   logAction({ req?, userId?, orgId?, action, entityType?, entityId?, data?, ip? })
 * req verilirse userId ve ip ondan alınır. `data` içinde parola/jeton gibi gizli alanları GEÇMEYİN.
 */
async function logAction(o = {}) {
  try {
    if (!o.action || typeof o.action !== "string") return false;
    const req = o.req;
    const userId = o.userId || (req && req.user && req.user.id) || null;
    const ip = o.ip || (req && req.ip) || null;
    const orgId = o.orgId || (await defaultOrgId());
    await db.query(
      `INSERT INTO audit_log (org_id, user_id, action, entity_type, entity_id, data, ip) VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [orgId, userId, String(o.action).slice(0, 100), o.entityType || null, o.entityId != null ? String(o.entityId).slice(0, 200) : null, JSON.stringify(o.data || {}), ip ? String(ip).slice(0, 64) : null]
    );
    return true;
  } catch (err) {
    console.error("audit.logAction hatası:", err.message);
    return false;
  }
}
module.exports = { logAction };
