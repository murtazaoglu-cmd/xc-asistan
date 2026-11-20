const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const { canAccessResource } = require("../middleware/ownership");
const { listAppointments, getAppointment } = require("../services/appointmentQueries");
const { parseGeoFields, pushGeoSets } = require("../services/helpers");

// Panel tür/durum değerlerini serbest metin olarak gönderir (örn. "kesif", "beklemede", "onaylandı");
// bu yüzden sabit liste yerine yalnızca makul bir uzunluk sınırı uygulanır.
const okLabel = (v) => typeof v === "string" && v.trim().length > 0 && v.length <= 40;
const okDate = (v) => (typeof v === "string" || typeof v === "number") && !Number.isNaN(new Date(v).getTime());

/** Randevuya erişim: admin/muhasebe hepsi; saha atandığı; diğerleri kendi/paylaşılan teklif-proje ya da kendi oluşturduğu */
async function canTouchAppointment(user, appt) {
  if (user.role === "admin" || user.role === "muhasebe") return true;
  if (String(appt.assigned_user_id) === String(user.id) || String(appt.owner_id) === String(user.id)) return true;
  if (user.role === "saha") return false;
  if (appt.offer_id) {
    const o = await db.query("SELECT owner_id FROM offers WHERE id = $1", [appt.offer_id]);
    if (o.rows[0] && (await canAccessResource(user, "offer", appt.offer_id, o.rows[0].owner_id))) return true;
  }
  if (appt.project_id) {
    const p = await db.query("SELECT owner_id FROM projects WHERE id = $1", [appt.project_id]);
    if (p.rows[0] && (await canAccessResource(user, "project", appt.project_id, p.rows[0].owner_id))) return true;
  }
  return false;
}

/** Bağlanacak teklif/projeye erişim şart. Hata varsa {status, error} döner, yoksa null */
async function checkLinks(user, offer_id, project_id) {
  if (offer_id) {
    const o = await db.query("SELECT owner_id FROM offers WHERE id = $1", [offer_id]);
    if (!o.rows[0]) return { status: 404, error: "Teklif bulunamadı." };
    if (!(await canAccessResource(user, "offer", offer_id, o.rows[0].owner_id))) return { status: 403, error: "Bu teklife erişiminiz yok." };
  }
  if (project_id) {
    const p = await db.query("SELECT owner_id FROM projects WHERE id = $1", [project_id]);
    if (!p.rows[0]) return { status: 404, error: "Proje bulunamadı." };
    if (!(await canAccessResource(user, "project", project_id, p.rows[0].owner_id))) return { status: 403, error: "Bu projeye erişiminiz yok." };
  }
  return null;
}

/**
 * Atanabilecek kişi: admin/muhasebe herkesi; ortak kendisi + kendi ekibi; diğerleri kendisi + kendi ekibi
 * (aynı lider altındakiler ve lider). Böylece bir ortağın randevusu başka bir ortağın ekibine atanamaz.
 */
async function canAssignTo(user, targetId) {
  if (String(targetId) === String(user.id)) return true;
  const t = await db.query("SELECT id, created_by FROM users WHERE id = $1", [targetId]);
  if (!t.rows[0]) return false;
  if (user.role === "admin" || user.role === "muhasebe") return true;
  if (user.role === "ortak") return String(t.rows[0].created_by) === String(user.id);
  const me = await db.query("SELECT created_by FROM users WHERE id = $1", [user.id]);
  const leader = me.rows[0]?.created_by;
  if (!leader) return false;
  return String(t.rows[0].id) === String(leader) || String(t.rows[0].created_by) === String(leader);
}

const router = express.Router();

/**
 * Randevular (ilişkili teklif/proje + müşteri adı/telefonu/adres hazır) — role göre kısıtlanır.
 * Opsiyonel filtreler: ?from=ISO (dahil) &to=ISO (hariç) &assigned_user_id=<uuid|me> &status=<metin>
 */
router.get("/", requireAuth, async (req, res) => {
  const where = []; const params = [];
  if (req.query.from) {
    if (!okDate(req.query.from)) return res.status(400).json({ error: "Geçersiz from tarihi." });
    params.push(req.query.from); where.push(`a.scheduled_at >= $${params.length}`);
  }
  if (req.query.to) {
    if (!okDate(req.query.to)) return res.status(400).json({ error: "Geçersiz to tarihi." });
    params.push(req.query.to); where.push(`a.scheduled_at < $${params.length}`);
  }
  if (req.query.assigned_user_id) {
    params.push(req.query.assigned_user_id === "me" ? req.user.id : req.query.assigned_user_id);
    where.push(`a.assigned_user_id = $${params.length}`);
  }
  if (req.query.status) { params.push(String(req.query.status)); where.push(`a.status = $${params.length}`); }
  res.json(await listAppointments(req.user, { extraWhere: where, extraParams: params }));
});

router.get("/:id", requireAuth, async (req, res) => {
  const cur = await db.query("SELECT * FROM appointments WHERE id = $1", [req.params.id]);
  if (!cur.rows[0]) return res.status(404).json({ error: "Randevu bulunamadı." });
  if (!(await canTouchAppointment(req.user, cur.rows[0]))) return res.status(403).json({ error: "Bu randevuya erişiminiz yok." });
  res.json(await getAppointment(req.params.id));
});

router.post("/", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const { type, scheduled_at, notes, offer_id, project_id, assigned_user_id, customer_name, customer_phone } = req.body;
  if (!type || !scheduled_at) return res.status(400).json({ error: "Tür ve tarih zorunludur." });
  if (!okLabel(type)) return res.status(400).json({ error: "Geçersiz randevu türü." });
  if (!okDate(scheduled_at)) return res.status(400).json({ error: "Geçersiz tarih." });
  const geo = parseGeoFields(req.body);
  if (geo.error) return res.status(400).json({ error: geo.error });
  for (const [v, n] of [[customer_name, "Müşteri adı"], [customer_phone, "Müşteri telefonu"]]) {
    if (v !== undefined && v !== null && (typeof v !== "string" || v.length > 200)) return res.status(400).json({ error: `${n} geçersiz.` });
  }

  const linkErr = await checkLinks(req.user, offer_id, project_id);
  if (linkErr) return res.status(linkErr.status).json({ error: linkErr.error });
  const assignee = assigned_user_id || req.user.id;
  if (!(await canAssignTo(req.user, assignee))) return res.status(403).json({ error: "Bu kişiye randevu atayamazsınız." });

  const g = geo.fields;
  const { rows } = await db.query(
    `INSERT INTO appointments (type, scheduled_at, notes, offer_id, project_id, assigned_user_id, owner_id, address, lat, lng, customer_name, customer_phone)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,
    [type, scheduled_at, notes || null, offer_id || null, project_id || null, assignee, req.user.id,
     g.address ?? null, g.lat ?? null, g.lng ?? null, customer_name || null, customer_phone || null]
  );
  res.status(201).json(await getAppointment(rows[0].id));
});

router.patch("/:id", requireAuth, async (req, res) => {
  const { status, scheduled_at, notes, type, offer_id, project_id, assigned_user_id, customer_name, customer_phone } = req.body;
  const cur = await db.query("SELECT * FROM appointments WHERE id = $1", [req.params.id]);
  if (!cur.rows[0]) return res.status(404).json({ error: "Randevu bulunamadı." });
  if (!(await canTouchAppointment(req.user, cur.rows[0]))) return res.status(403).json({ error: "Bu randevuya erişiminiz yok." });

  // Saha yalnızca durum / not / tarih güncelleyebilir; bağlantı, atama, adres değişikliği yönetim işidir
  const structural = [type, offer_id, project_id, assigned_user_id, customer_name, customer_phone, req.body.address, req.body.lat, req.body.lng];
  if (req.user.role === "saha" && structural.some((v) => v !== undefined)) {
    return res.status(403).json({ error: "Saha yalnızca durum, not ve tarih güncelleyebilir." });
  }
  if (status && !okLabel(status)) return res.status(400).json({ error: "Geçersiz durum." });
  if (type !== undefined && !okLabel(type)) return res.status(400).json({ error: "Geçersiz randevu türü." });
  if (scheduled_at !== undefined && !okDate(scheduled_at)) return res.status(400).json({ error: "Geçersiz tarih." });
  const geo = parseGeoFields(req.body);
  if (geo.error) return res.status(400).json({ error: geo.error });
  for (const [v, n] of [[customer_name, "Müşteri adı"], [customer_phone, "Müşteri telefonu"]]) {
    if (v !== undefined && v !== null && (typeof v !== "string" || v.length > 200)) return res.status(400).json({ error: `${n} geçersiz.` });
  }
  const linkErr = await checkLinks(req.user, offer_id || null, project_id || null);
  if (linkErr) return res.status(linkErr.status).json({ error: linkErr.error });
  if (assigned_user_id && !(await canAssignTo(req.user, assigned_user_id))) {
    return res.status(403).json({ error: "Bu kişiye randevu atayamazsınız." });
  }

  const sets = []; const params = []; let i = 1;
  if (status) { sets.push(`status = $${i++}`); params.push(status); }
  if (scheduled_at) { sets.push(`scheduled_at = $${i++}`); params.push(scheduled_at); }
  if (notes !== undefined) { sets.push(`notes = $${i++}`); params.push(notes); }
  if (type !== undefined) { sets.push(`type = $${i++}`); params.push(type); }
  if (offer_id !== undefined) { sets.push(`offer_id = $${i++}`); params.push(offer_id || null); }
  if (project_id !== undefined) { sets.push(`project_id = $${i++}`); params.push(project_id || null); }
  if (assigned_user_id !== undefined) { sets.push(`assigned_user_id = $${i++}`); params.push(assigned_user_id || null); }
  if (customer_name !== undefined) { sets.push(`customer_name = $${i++}`); params.push(customer_name || null); }
  if (customer_phone !== undefined) { sets.push(`customer_phone = $${i++}`); params.push(customer_phone || null); }
  i = pushGeoSets(geo.fields, sets, params, i);
  if (sets.length === 0) return res.status(400).json({ error: "Güncellenecek alan yok." });
  params.push(req.params.id);
  const { rowCount } = await db.query(`UPDATE appointments SET ${sets.join(", ")} WHERE id = $${i}`, params);
  if (!rowCount) return res.status(404).json({ error: "Randevu bulunamadı." });
  res.json(await getAppointment(req.params.id));
});

router.delete("/:id", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const cur = await db.query("SELECT * FROM appointments WHERE id = $1", [req.params.id]);
  if (!cur.rows[0]) return res.status(404).json({ error: "Randevu bulunamadı." });
  if (!(await canTouchAppointment(req.user, cur.rows[0]))) return res.status(403).json({ error: "Bu randevuya erişiminiz yok." });
  await db.query("DELETE FROM appointments WHERE id = $1", [req.params.id]);
  res.json({ message: "Silindi." });
});

module.exports = router;
