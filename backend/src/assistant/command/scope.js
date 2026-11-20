/**
 * Komut çubuğu / içe aktarma için KULLANICI KAPSAMI: kullanıcının görebildiği müşteri havuzu, rol matrisi, telefon anahtarı.
 * Kural, mevcut REST uçlarıyla aynıdır (GET /customers, scopeClause, appointmentScope): asistanın yetkisi kullanıcının yetkisini AŞAMAZ.
 *   admin/muhasebe → hepsi · ortak → yalnız kendi (owner_id) · personel → kendi/paylaşılan teklifler + kendi müşterileri · saha → müşteri havuzu YOK
 * ortak A, ortak B'nin müşterisini görmez ve eşleyemez (havuz SQL ile süzülür; sonradan süzme yoktur).
 */
const db = require("../../db");

const POOL_LIMIT = 3000;

/** Telefondan karşılaştırma anahtarı: yalnız rakamların son 10 hanesi (0532…, +90532…, 90532… aynı müşteri). 7 haneden kısa → null */
function tail10(phone) {
  const d = String(phone == null ? "" : phone).replace(/\D/g, "");
  return d.length >= 7 ? d.slice(-10) : null;
}

/** Niyet → izinli roller. Yazma niyetleri REST'teki requireRole kurallarıyla uyumludur (confirm'de REST yine denetler). */
const ALL = ["admin", "muhasebe", "ortak", "personel", "saha"];
const NO_SAHA = ["admin", "muhasebe", "ortak", "personel"];
const ROLE_MATRIX = {
  "appointment.create": NO_SAHA,
  "appointment.reschedule": ALL,
  "appointment.cancel": ALL,
  "reminder.create": ALL,
  "payment.add": NO_SAHA,        // saha finans komutu kullanamaz
  "expense.add": NO_SAHA,
  "offer.status": NO_SAHA,
  "note.add": ALL,
  "query.agenda": ALL,
  "query.appointments": ALL,
  "query.collections": NO_SAHA,  // finans okuma
  "query.expenses": NO_SAHA,
  "query.receivables": NO_SAHA,
  "customer.search": NO_SAHA,
};
const WRITE_INTENTS = new Set(["appointment.create", "appointment.reschedule", "appointment.cancel", "reminder.create", "payment.add", "expense.add", "offer.status", "note.add"]);
const roleAllows = (intent, role) => (ROLE_MATRIX[intent] || []).includes(role);

/** Rolün müşteri havuzu SQL kapsamı: offers (alias o) ve customers (alias c) için WHERE parçaları + parametreler */
function poolScope(user) {
  if (user.role === "admin" || user.role === "muhasebe") return { offers: "TRUE", customers: "TRUE", params: [] };
  if (user.role === "ortak") return { offers: "o.owner_id = $1", customers: "c.owner_id = $1", params: [user.id] };
  if (user.role === "personel") {
    return {
      offers: "(o.owner_id = $1 OR o.id IN (SELECT resource_id FROM resource_shares WHERE resource_type = 'offer' AND shared_with_user_id = $1))",
      customers: "c.owner_id = $1", params: [user.id],
    };
  }
  return null; // saha: havuz yok
}

/** Kullanıcının görebildiği müşteriler: [{key (tail10), name, phone, address}] — en yeni kayıttaki ad/telefon */
async function customerPool(user, client = db) {
  const sc = poolScope(user);
  if (!sc) return [];
  const { rows } = await client.query(
    `SELECT DISTINCT ON (k) k AS key, name, phone, address FROM (
        SELECT right(regexp_replace(o.phone, '[^0-9]', '', 'g'), 10) AS k, o.name, o.phone, o.address, o.created_at FROM offers o WHERE ${sc.offers}
        UNION ALL
        SELECT right(regexp_replace(c.phone, '[^0-9]', '', 'g'), 10) AS k, c.name, c.phone, c.address, c.created_at FROM customers c WHERE ${sc.customers}
     ) x WHERE length(k) >= 7 AND name IS NOT NULL ORDER BY k, created_at DESC LIMIT ${POOL_LIMIT}`,
    sc.params
  );
  return rows;
}

/** Havuzda bu anahtar var mı (UUID/anahtar uydurmaya karşı; seçimler yalnız havuzdan gelebilir) */
async function poolEntry(user, key) {
  const k = tail10(key) || (/^\d{7,10}$/.test(String(key)) ? String(key) : null);
  if (!k) return null;
  const pool = await customerPool(user);
  return pool.find((p) => p.key === k) || null;
}

module.exports = { tail10, ROLE_MATRIX, WRITE_INTENTS, roleAllows, poolScope, customerPool, poolEntry, POOL_LIMIT };
