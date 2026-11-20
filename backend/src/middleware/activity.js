const db = require("../db");

/** Bir teklif/proje üzerindeki işlemi geçmişe kaydeder. Hata olsa bile ana işlemi bozmasın diye sessizce yutar. */
async function logActivity(resourceType, resourceId, userId, action, details) {
  try {
    await db.query(
      "INSERT INTO activity_log (resource_type, resource_id, user_id, action, details) VALUES ($1,$2,$3,$4,$5)",
      [resourceType, resourceId, userId || null, action, details || null]
    );
  } catch (err) {
    console.error("Aktivite logu kaydedilemedi:", err.message);
  }
}

module.exports = { logActivity };
