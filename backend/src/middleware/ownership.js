const db = require("../db");

/**
 * Bir kullanıcının verilen kaynağa (offer/project) erişimi olup olmadığını kontrol eder.
 * admin/muhasebe her zaman erişebilir. Diğerleri sadece kendi sahip oldukları
 * ya da kendileriyle paylaşılan kayıtlara erişebilir.
 */
async function canAccessResource(user, resourceType, resourceId, ownerIdOfResource) {
  if (user.role === "admin" || user.role === "muhasebe") return true;
  if (ownerIdOfResource && ownerIdOfResource === user.id) return true;

  const { rows } = await db.query(
    "SELECT 1 FROM resource_shares WHERE resource_type = $1 AND resource_id = $2 AND shared_with_user_id = $3",
    [resourceType, resourceId, user.id]
  );
  return rows.length > 0;
}

/** GET listeleri için WHERE koşulu üretir (parametreli). role=admin/muhasebe ise kısıtlama yoktur. */
function scopeClause(user, tableAlias, resourceType, paramIndexStart) {
  if (user.role === "admin" || user.role === "muhasebe") {
    return { clause: "", params: [] };
  }
  const p1 = paramIndexStart;
  const p2 = paramIndexStart + 1;
  const clause = `AND (${tableAlias}.owner_id = $${p1} OR ${tableAlias}.id IN (
    SELECT resource_id FROM resource_shares WHERE resource_type = '${resourceType}' AND shared_with_user_id = $${p2}
  ))`;
  return { clause, params: [user.id, user.id] };
}

module.exports = { canAccessResource, scopeClause };
