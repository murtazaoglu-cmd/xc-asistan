const db = require("../db");

/**
 * Randevu sorguları (panel, dashboard-init ve mobil ana ekran ortak kullanır).
 * Telefon/adres randevu cevabında hazır gelir:
 *   customer_name  = randevunun kendi müşteri adı → teklif adı → proje müşterisi → projenin teklifi
 *   customer_phone = randevunun kendi telefonu → teklif → projenin teklifi
 *   address/lat/lng = ilk dolu kaynak: randevu → teklif → proje → projenin teklifi (üçü aynı kaynaktan)
 * Eski alanlar korunur: offer_name, offer_phone, offer_service, project_customer, project_code.
 */
const APPT_SELECT = `
  SELECT a.id, a.offer_id, a.project_id, a.type, a.scheduled_at, a.assigned_user_id, a.notes, a.status, a.owner_id,
    COALESCE(a.customer_name, o.name, p.customer_name, po.name) AS customer_name,
    COALESCE(a.customer_phone, o.phone, po.phone) AS customer_phone,
    loc.address AS address, loc.lat AS lat, loc.lng AS lng,
    COALESCE(o.service, p.service, po.service) AS service,
    u.name AS assigned_user_name,
    o.name AS offer_name, o.phone AS offer_phone, o.service AS offer_service, o.code AS offer_code,
    p.customer_name AS project_customer, p.code AS project_code
  FROM appointments a
  LEFT JOIN offers o ON o.id = a.offer_id
  LEFT JOIN projects p ON p.id = a.project_id
  LEFT JOIN offers po ON po.id = p.offer_id
  LEFT JOIN users u ON u.id = a.assigned_user_id
  LEFT JOIN LATERAL (
    SELECT v.address, v.lat, v.lng FROM (VALUES
      (1, a.address, a.lat, a.lng), (2, o.address, o.lat, o.lng),
      (3, p.address, p.lat, p.lng), (4, po.address, po.lat, po.lng)
    ) v(pri, address, lat, lng)
    WHERE v.address IS NOT NULL OR v.lat IS NOT NULL ORDER BY v.pri LIMIT 1
  ) loc ON true
`;

/**
 * Kullanıcının görebileceği randevular için WHERE parçası (APPT_SELECT'in a/o/p takma adlarıyla).
 *  admin/muhasebe → hepsi
 *  diğer roller   → kendi oluşturduğu, kendisine atanan, kendi/paylaşılan teklif ve projelere bağlı olanlar
 *  Başka bir ortağın (ortak) randevusu hiçbir koşulda dönmez.
 */
function appointmentScope(user, paramIndex) {
  if (user.role === "admin" || user.role === "muhasebe") return { clause: "", params: [] };
  const i = paramIndex;
  return {
    clause: `(
      a.owner_id = $${i} OR a.assigned_user_id = $${i}
      OR o.owner_id = $${i} OR o.id IN (SELECT resource_id FROM resource_shares WHERE resource_type='offer' AND shared_with_user_id = $${i})
      OR p.owner_id = $${i} OR p.id IN (SELECT resource_id FROM resource_shares WHERE resource_type='project' AND shared_with_user_id = $${i})
    )`,
    params: [user.id],
  };
}

async function listAppointments(user, { extraWhere = [], extraParams = [], order = "a.scheduled_at ASC", limit } = {}) {
  const params = [...extraParams];
  const where = [...extraWhere];
  const sc = appointmentScope(user, params.length + 1);
  if (sc.clause) { where.push(sc.clause); params.push(...sc.params); }
  const sql = `${APPT_SELECT} ${where.length ? "WHERE " + where.join(" AND ") : ""} ORDER BY ${order}${limit ? ` LIMIT ${Number(limit)}` : ""}`;
  const { rows } = await db.query(sql, params);
  return rows;
}

async function getAppointment(id) {
  const { rows } = await db.query(`${APPT_SELECT} WHERE a.id = $1`, [id]);
  return rows[0] || null;
}

module.exports = { APPT_SELECT, appointmentScope, listAppointments, getAppointment };
