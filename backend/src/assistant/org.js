const db = require("../db");

/** Varsayılan kuruluş (tek kuruluşlu dönem). Süreç içi önbellek; kuruluşlar silinmediği için güvenli. */
let cachedDefault = null;
async function defaultOrgId() {
  if (cachedDefault) return cachedDefault;
  const { rows } = await db.query("SELECT id FROM organizations WHERE is_default LIMIT 1");
  cachedDefault = rows[0] ? rows[0].id : null;
  return cachedDefault;
}
/** Kullanıcının kuruluşu (users.org_id; yoksa varsayılan) */
async function orgIdForUser(userId, client = db) {
  if (userId) {
    const { rows } = await client.query("SELECT org_id FROM users WHERE id = $1", [userId]);
    if (rows[0] && rows[0].org_id) return rows[0].org_id;
  }
  return defaultOrgId();
}
function _resetCache() { cachedDefault = null; }
module.exports = { defaultOrgId, orgIdForUser, _resetCache };
