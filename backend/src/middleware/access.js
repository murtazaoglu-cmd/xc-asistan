const db = require("../db");

/**
 * Ortak yetki yardımcıları.
 *
 * Model: admin ve muhasebe "işletme" tarafıdır; finans kayıtları (ödeme/gider) ilk admin'in
 * defterine yazılır. ortak ve personel kendi defterlerine yazar ve yalnız kendi kayıtlarını görür.
 */

let cachedAdminId = null;
async function firstAdminId() {
  if (cachedAdminId) return cachedAdminId;
  const { rows } = await db.query("SELECT id FROM users WHERE role = 'admin' ORDER BY created_at ASC LIMIT 1");
  cachedAdminId = rows[0]?.id || null;
  return cachedAdminId;
}

/** Bu kullanıcının finans defteri sahibi: muhasebe → ilk admin, diğerleri → kendisi */
async function financeOwnerId(user) {
  if (user.role === "muhasebe") return (await firstAdminId()) || user.id;
  return user.id;
}

/**
 * Yeni finans kaydı (ödeme/gider) için owner_id.
 *
 * Varsayılan: kaydı yazan kişinin KENDİ defteri. Gövdeden gelen owner_id (başkasına atama) yalnızca şu durumlarda kabul edilir:
 *  - admin: sistemde var olan herhangi bir kullanıcıya;
 *  - muhasebe veya PROJENİN SAHİBİ: projenin sahibine ya da projeyle paylaşılmış bir kullanıcıya.
 * Projeyle yalnızca paylaşılmış (işbirlikçi) bir kullanıcı ASLA başkasının defterine kayıt yazamaz: istek sessizce
 * kendi defterine düşer. (Önceki sürümde "hedef projeyle ilişkili mi" kontrol ediliyor, "isteyen hedef adına yazabilir mi"
 * kontrol edilmiyordu — F-22.) projectId yoksa (genel gider) yalnız admin başkasına atayabilir.
 */
async function resolveFinanceOwner(user, requestedOwnerId, projectId) {
  const own = await financeOwnerId(user);
  if (!requestedOwnerId || String(requestedOwnerId) === String(own)) return own;
  if (user.role === "admin") {
    const { rows } = await db.query("SELECT 1 FROM users WHERE id = $1", [requestedOwnerId]);
    return rows[0] ? requestedOwnerId : own;
  }
  if (!projectId) return own;
  const proj = await db.query("SELECT owner_id FROM projects WHERE id = $1", [projectId]);
  if (!proj.rows[0]) return own;
  const mayAssign = user.role === "muhasebe" || String(proj.rows[0].owner_id) === String(user.id);
  if (!mayAssign) return own;
  const { rows } = await db.query(
    `SELECT 1 FROM projects WHERE id = $1 AND owner_id = $2
     UNION ALL
     SELECT 1 FROM resource_shares WHERE resource_type = 'project' AND resource_id = $1 AND shared_with_user_id = $2`,
    [projectId, requestedOwnerId]
  );
  return rows[0] ? requestedOwnerId : own;
}

/** Bir finans satırını (payments/expenses) değiştirme/silme yetkisi */
async function canModifyFinanceRow(user, row) {
  if (!row) return false;
  if (user.role === "admin") return true;
  const own = await financeOwnerId(user);
  return String(row.owner_id) === String(own);
}

/** Ortak, sadece kendi oluşturduğu kullanıcıları kapsar; admin hepsini */
function isTenantUser(user) {
  return user.role === "ortak";
}

module.exports = { firstAdminId, financeOwnerId, resolveFinanceOwner, canModifyFinanceRow, isTenantUser };
