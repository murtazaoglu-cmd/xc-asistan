const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const { canAccessResource, scopeClause } = require("../middleware/ownership");
const { logActivity } = require("../middleware/activity");
const push = require("../services/push");
const { financeOwnerId, resolveFinanceOwner, canModifyFinanceRow } = require("../middleware/access");
const { parseGeoFields, pushGeoSets, parseListParams, searchClause, queryList, sendList } = require("../services/helpers");

function posAmount(v) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}
function nonNegAmount(v) {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

/** Görev atanabilecek kişi: proje sahibi ya da projeyle paylaşılmış kullanıcı (POST ve PATCH aynı kuralı kullanır) */
async function isProjectMember(projectId, userId) {
  const ok = await db.query(
    `SELECT 1 FROM projects WHERE id = $1 AND owner_id = $2
     UNION ALL SELECT 1 FROM resource_shares WHERE resource_type='project' AND resource_id = $1 AND shared_with_user_id = $2`,
    [projectId, userId]
  );
  return !!ok.rows[0];
}

/** Görev/ilave iş gibi alt kaynaklarda: kaydın ait olduğu projeye erişim kontrolü */
async function checkChildAccess(req, res, table, id) {
  const { rows } = await db.query(`SELECT project_id FROM ${table} WHERE id = $1`, [id]);
  if (!rows[0]) { res.status(404).json({ error: "Kayıt bulunamadı." }); return null; }
  if (!(await checkProjectAccess(req, res, rows[0].project_id))) return null;
  return rows[0];
}

const router = express.Router();

/** Ortak yardımcı: proje sahiplik/paylaşım kontrolü, bulunamazsa/erişim yoksa uygun hatayı döner */
async function checkProjectAccess(req, res, projectId) {
  const { rows } = await db.query("SELECT owner_id FROM projects WHERE id = $1", [projectId]);
  if (!rows[0]) { res.status(404).json({ error: "Proje bulunamadı." }); return false; }
  const allowed = await canAccessResource(req.user, "project", projectId, rows[0].owner_id);
  if (!allowed) { res.status(403).json({ error: "Bu projeye erişiminiz yok." }); return false; }
  return true;
}

router.get("/", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const pg = parseListParams(req);
  // paid_amount: yalnız ÇAĞIRANIN defterindeki (owner_id = financeOwnerId) tahsilat — "ayrı firma" modeli (F-24)
  const params = [await financeOwnerId(req.user)];
  let sql = `
    SELECT p.*,
      COALESCE((SELECT SUM(amount) FROM payments WHERE project_id = p.id AND owner_id = $1), 0) AS paid_amount
    FROM projects p WHERE 1=1
  `;
  const scope = scopeClause(req.user, "p", "project", 2);
  sql += ` ${scope.clause}`;
  params.push(...scope.params);
  // ?q= arama: müşteri adı, kod, hizmet, adres, not; ?limit/&offset sayfalama
  sql += searchClause(pg, ["p.customer_name", "p.code", "p.service", "p.address", "p.notes"], null, params);
  sendList(res, pg, await queryList(sql, params, "ORDER BY p.start_date DESC, p.id", pg));
});

/** Manuel proje oluştur (teklif akışından bağımsız — örn. eski/telefonla anlaşılan iş) */
router.post("/", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const { customer_name, service, total_amount, stage } = req.body;
  if (!customer_name || !service) {
    return res.status(400).json({ error: "Müşteri adı ve hizmet türü zorunludur." });
  }
  const geo = parseGeoFields(req.body);
  if (geo.error) return res.status(400).json({ error: geo.error });
  const g = geo.fields;
  const total = total_amount === undefined || total_amount === "" ? 0 : nonNegAmount(total_amount);
  if (total === null) return res.status(400).json({ error: "Geçerli bir tutar girin." });
  const validStages = ["Malzeme Temini", "Üretim", "Montaj", "Teslim", "Tamamlandı"];
  const finalStage = validStages.includes(stage) ? stage : "Malzeme Temini";
  const { rows: seq } = await db.query("SELECT 'PRJ-' || nextval('project_code_seq') AS code");
  const { rows } = await db.query(
    `INSERT INTO projects (code, customer_name, service, total_amount, stage, owner_id, address, lat, lng)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
    [seq[0].code, customer_name, service, total, finalStage, req.user.id, g.address ?? null, g.lat ?? null, g.lng ?? null]
  );
  res.status(201).json(rows[0]);
});

/** Tüm projelerdeki tamamlanmamış görevler — tek listede ("Bekleyen İşler") */
router.get("/tasks/pending", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const params = [];
  let sql = `
    SELECT t.*, p.customer_name, p.code AS project_code, p.service AS project_service
    FROM project_tasks t
    JOIN projects p ON p.id = t.project_id
    WHERE t.status != 'tamamlandi'
  `;
  const scope = scopeClause(req.user, "p", "project", 1);
  sql += ` ${scope.clause}`;
  params.push(...scope.params);
  sql += " ORDER BY t.created_at ASC";
  const { rows } = await db.query(sql, params);
  res.json(rows);
});

/** Tüm projelerdeki tüm ödemeler (Finans sekmesi "Tüm Ödemeler" listesi için) */
router.get("/payments/all", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const params = [];
  let sql = `
    SELECT pay.*, p.customer_name, p.code AS project_code
    FROM payments pay
    JOIN projects p ON p.id = pay.project_id
    WHERE pay.owner_id = $1
  `;
  params.push(await financeOwnerId(req.user));
  sql += " ORDER BY pay.paid_at DESC";
  const { rows } = await db.query(sql, params);
  res.json(rows);
});

router.patch("/:id/stage", requireAuth, async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { stage } = req.body;
  const valid = ["Malzeme Temini", "Üretim", "Montaj", "Teslim", "Tamamlandı"];
  if (!valid.includes(stage)) return res.status(400).json({ error: "Geçersiz aşama." });

  const { rows } = await db.query(
    "UPDATE projects SET stage = $1, end_date = CASE WHEN $1 = 'Tamamlandı' THEN now() ELSE end_date END WHERE id = $2 RETURNING *",
    [stage, req.params.id]
  );
  logActivity("project", req.params.id, req.user.id, "asama_degisti", stage);
  res.json(rows[0]);
});

router.patch("/:id/amount", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const total = nonNegAmount(req.body.total_amount);
  if (total === null) return res.status(400).json({ error: "Geçerli bir tutar girin." });
  const { rows } = await db.query(
    "UPDATE projects SET total_amount = $1 WHERE id = $2 RETURNING *",
    [total, req.params.id]
  );
  res.json(rows[0]);
});

// --- Başlama / Bitiş Tarihleri (randevu listesine otomatik yansır) ---

router.patch("/:id/dates", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { start_date, end_date } = req.body;
  const projectId = req.params.id;

  const sets = []; const params = []; let i = 1;
  if (start_date) { sets.push(`start_date = $${i++}`); params.push(start_date); }
  if (end_date !== undefined) { sets.push(`end_date = $${i++}`); params.push(end_date || null); }
  if (sets.length === 0) return res.status(400).json({ error: "Güncellenecek tarih yok." });
  params.push(projectId);

  const { rows } = await db.query(
    `UPDATE projects SET ${sets.join(", ")} WHERE id = $${i} RETURNING *`,
    params
  );
  const project = rows[0];

  async function upsertAppointment(type, date) {
    if (!date) return;
    const existing = await db.query(
      "SELECT id FROM appointments WHERE project_id = $1 AND type = $2",
      [projectId, type]
    );
    if (existing.rows[0]) {
      await db.query("UPDATE appointments SET scheduled_at = $1 WHERE id = $2", [date, existing.rows[0].id]);
    } else {
      await db.query(
        "INSERT INTO appointments (type, scheduled_at, project_id, notes, owner_id) VALUES ($1,$2,$3,$4,$5)",
        [type, date, projectId, `${project.customer_name} — ${project.service}`, project.owner_id || req.user.id]
      );
    }
  }

  if (start_date) await upsertAppointment("baslama", start_date);
  if (end_date !== undefined) await upsertAppointment("teslim", end_date);

  res.json(project);
});

// --- Ödemeler ---

router.post("/:id/payments", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { amount, method, note, paid_at, owner_id } = req.body;
  const amt = posAmount(amount);
  const METHODS = ["Havale", "Nakit", "Kredi Kartı"];
  if (amt === null || !method) return res.status(400).json({ error: "Geçerli tutar ve yöntem zorunludur." });
  if (!METHODS.includes(method)) return res.status(400).json({ error: "Geçersiz ödeme yöntemi." });
  const finalOwner = await resolveFinanceOwner(req.user, owner_id, req.params.id);

  const { rows } = await db.query(
    "INSERT INTO payments (project_id, amount, method, note, paid_at, owner_id) VALUES ($1,$2,$3,$4,COALESCE($5, now()),$6) RETURNING *",
    [req.params.id, amt, method, note || null, paid_at || null, finalOwner]
  );
  logActivity("project", req.params.id, req.user.id, "odeme_eklendi", `${amt} ₺ (${method})`);
  if (String(finalOwner) !== String(await financeOwnerId(req.user))) {
    push.notifyUser(finalOwner, "Size bir ödeme atandı", `${req.user.name || "Bir kullanıcı"}: ${amt} ₺ (${method})`, "/finans");
  }
  res.status(201).json(rows[0]);
});

router.get("/:id/payments", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { rows } = await db.query(
    "SELECT * FROM payments WHERE project_id = $1 AND owner_id = $2 ORDER BY paid_at DESC",
    [req.params.id, await financeOwnerId(req.user)]
  );
  res.json(rows);
});

/** Bir ödemeyi düzenle (tutar, yöntem, not, tarih) — yanlış girilen ödemeleri düzeltmek için */
router.patch("/payments/:paymentId", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const { amount, method, note, paid_at, owner_id } = req.body;
  const existing = await db.query("SELECT project_id, owner_id FROM payments WHERE id = $1", [req.params.paymentId]);
  if (!existing.rows[0]) return res.status(404).json({ error: "Ödeme bulunamadı." });
  if (!(await checkProjectAccess(req, res, existing.rows[0].project_id))) return;
  if (!(await canModifyFinanceRow(req.user, existing.rows[0]))) {
    return res.status(403).json({ error: "Bu ödeme size ait değil." });
  }

  const sets = []; const params = []; let i = 1;
  if (amount !== undefined) {
    const amt = posAmount(amount);
    if (amt === null) return res.status(400).json({ error: "Geçerli bir tutar girin." });
    sets.push(`amount = $${i++}`); params.push(amt);
  }
  if (method !== undefined) { sets.push(`method = $${i++}`); params.push(method); }
  if (note !== undefined) { sets.push(`note = $${i++}`); params.push(note); }
  if (paid_at !== undefined) { sets.push(`paid_at = $${i++}`); params.push(paid_at); }
  if (owner_id !== undefined) {
    const finalOwner = await resolveFinanceOwner(req.user, owner_id, existing.rows[0].project_id);
    sets.push(`owner_id = $${i++}`); params.push(finalOwner);
  }
  if (sets.length === 0) return res.status(400).json({ error: "Güncellenecek alan yok." });
  params.push(req.params.paymentId);
  const { rows } = await db.query(`UPDATE payments SET ${sets.join(", ")} WHERE id = $${i} RETURNING *`, params);
  logActivity("project", existing.rows[0].project_id, req.user.id, "duzenlendi", "Ödeme güncellendi");
  res.json(rows[0]);
});

/** Bir ödemeyi sil — yanlışlıkla girilmiş bir kaydı kaldırmak için */
router.delete("/payments/:paymentId", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const existing = await db.query("SELECT project_id, owner_id FROM payments WHERE id = $1", [req.params.paymentId]);
  if (!existing.rows[0]) return res.status(404).json({ error: "Ödeme bulunamadı." });
  if (!(await checkProjectAccess(req, res, existing.rows[0].project_id))) return;
  if (!(await canModifyFinanceRow(req.user, existing.rows[0]))) {
    return res.status(403).json({ error: "Bu ödeme size ait değil." });
  }
  await db.query("DELETE FROM payments WHERE id = $1", [req.params.paymentId]);
  res.json({ message: "Ödeme silindi." });
});

// --- Proje Detayı (tam) ---

/** Bu projeye erişimi olan kullanıcılar (sahip + kendisiyle paylaşılanlar) —
 *  görev/gider/ödeme atama seçicisinde kullanılır. */
router.get("/:id/collaborators", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { rows } = await db.query(`
    SELECT DISTINCT u.id, u.name, u.role
    FROM users u
    WHERE u.id = (SELECT owner_id FROM projects WHERE id = $1)
       OR u.id IN (SELECT shared_with_user_id FROM resource_shares WHERE resource_type = 'project' AND resource_id = $1)
    ORDER BY u.name ASC
  `, [req.params.id]);
  res.json(rows);
});

router.get("/:id/full", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const id = req.params.id;

  // Görevler ortak/görünür kalır (koordinasyon için), ödeme ve giderler ise
  // sadece isteği yapan kullanıcıya ait olanlar döner ("ortak proje, ayrı firma" modeli).
  const ledgerOwnerId = await financeOwnerId(req.user);

  const [project, tasks, extras, payments, expenses] = await Promise.all([
    db.query("SELECT * FROM projects WHERE id = $1", [id]),
    db.query("SELECT * FROM project_tasks WHERE project_id = $1 ORDER BY sort_order, created_at", [id]),
    db.query("SELECT * FROM project_extras WHERE project_id = $1 ORDER BY created_at DESC", [id]),
    db.query("SELECT * FROM payments WHERE project_id = $1 AND owner_id = $2 ORDER BY paid_at DESC", [id, ledgerOwnerId]),
    db.query("SELECT * FROM expenses WHERE project_id = $1 AND owner_id = $2 ORDER BY expense_date DESC", [id, ledgerOwnerId]),
  ]);
  res.json({
    project: project.rows[0],
    tasks: tasks.rows,
    extras: extras.rows,
    payments: payments.rows,
    expenses: expenses.rows,
  });
});

// --- Görevler (yapılacak/yapılan işler) ---

router.get("/:id/tasks", requireAuth, async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { rows } = await db.query(
    "SELECT * FROM project_tasks WHERE project_id = $1 ORDER BY sort_order, created_at",
    [req.params.id]
  );
  res.json(rows);
});

router.post("/:id/tasks", requireAuth, async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { title, assigned_user_id } = req.body;
  if (!title) return res.status(400).json({ error: "Başlık zorunludur." });
  let finalAssignee = req.user.id;
  if (assigned_user_id && String(assigned_user_id) !== String(req.user.id)) {
    if (!(await isProjectMember(req.params.id, assigned_user_id))) return res.status(400).json({ error: "Görev yalnızca projedeki kişilere atanabilir." });
    finalAssignee = assigned_user_id;
  }
  const { rows } = await db.query(
    "INSERT INTO project_tasks (project_id, title, assigned_user_id) VALUES ($1,$2,$3) RETURNING *",
    [req.params.id, title, finalAssignee]
  );
  if (assigned_user_id && String(assigned_user_id) !== String(req.user.id)) {
    push.notifyUser(assigned_user_id, "Size yeni bir görev atandı", `${req.user.name || "Bir kullanıcı"}: "${title}"`, "/projeler");
  }
  res.status(201).json(rows[0]);
});

router.patch("/tasks/:taskId", requireAuth, async (req, res) => {
  const child = await checkChildAccess(req, res, "project_tasks", req.params.taskId);
  if (!child) return;
  const { status, title, assigned_user_id } = req.body;
  const valid = ["bekliyor", "devam_ediyor", "tamamlandi"];
  const sets = [];
  const params = [];
  let i = 1;
  if (status) {
    if (!valid.includes(status)) return res.status(400).json({ error: "Geçersiz durum." });
    sets.push(`status = $${i++}`); params.push(status);
    sets.push(`completed_at = ${status === "tamamlandi" ? "now()" : "NULL"}`);
  }
  if (title) { sets.push(`title = $${i++}`); params.push(title); }
  let newAssignee = null;
  if (assigned_user_id !== undefined) {
    // POST ile aynı kural: yalnız projedeki kişilere (sahip/paylaşılan) atanabilir; null/"" atamayı kaldırır (F-23)
    if (assigned_user_id === null || assigned_user_id === "") { sets.push(`assigned_user_id = $${i++}`); params.push(null); }
    else {
      if (typeof assigned_user_id !== "string") return res.status(400).json({ error: "Geçersiz kullanıcı." });
      if (String(assigned_user_id) !== String(req.user.id) && !(await isProjectMember(child.project_id, assigned_user_id))) {
        return res.status(400).json({ error: "Görev yalnızca projedeki kişilere atanabilir." });
      }
      sets.push(`assigned_user_id = $${i++}`); params.push(assigned_user_id);
      if (String(assigned_user_id) !== String(req.user.id)) newAssignee = assigned_user_id;
    }
  }
  if (sets.length === 0) return res.status(400).json({ error: "Güncellenecek alan yok." });
  params.push(req.params.taskId);
  const { rows } = await db.query(
    `UPDATE project_tasks SET ${sets.join(", ")} WHERE id = $${i} RETURNING *`,
    params
  );
  if (!rows[0]) return res.status(404).json({ error: "Görev bulunamadı." });
  if (newAssignee) push.notifyUser(newAssignee, "Size yeni bir görev atandı", `${req.user.name || "Bir kullanıcı"}: "${rows[0].title}"`, "/projeler");
  res.json(rows[0]);
});

router.delete("/tasks/:taskId", requireAuth, async (req, res) => {
  if (!(await checkChildAccess(req, res, "project_tasks", req.params.taskId))) return;
  await db.query("DELETE FROM project_tasks WHERE id = $1", [req.params.taskId]);
  res.json({ message: "Silindi." });
});

// --- İlave İşler (teslim öncesi çıkan ek maliyetler) ---

router.get("/:id/extras", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { rows } = await db.query(
    "SELECT * FROM project_extras WHERE project_id = $1 ORDER BY created_at DESC",
    [req.params.id]
  );
  res.json(rows);
});

router.post("/:id/extras", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { description } = req.body;
  const amount = Number(req.body.amount);
  if (!description || req.body.amount == null || !Number.isFinite(amount)) {
    return res.status(400).json({ error: "Açıklama ve geçerli bir tutar zorunludur." });
  }
  const { rows } = await db.query(
    "INSERT INTO project_extras (project_id, description, amount) VALUES ($1,$2,$3) RETURNING *",
    [req.params.id, description, amount]
  );
  res.status(201).json(rows[0]);
});

router.delete("/extras/:extraId", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkChildAccess(req, res, "project_extras", req.params.extraId))) return;
  await db.query("DELETE FROM project_extras WHERE id = $1", [req.params.extraId]);
  res.json({ message: "Silindi." });
});

// --- Giderler (proje bazlı) ---

router.get("/:id/expenses", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { rows } = await db.query(
    "SELECT * FROM expenses WHERE project_id = $1 AND owner_id = $2 ORDER BY expense_date DESC",
    [req.params.id, await financeOwnerId(req.user)]
  );
  res.json(rows);
});

router.post("/:id/expenses", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { category, amount, note, owner_id } = req.body;
  const amt = posAmount(amount);
  if (!category || amt === null) return res.status(400).json({ error: "Kategori ve geçerli bir tutar zorunludur." });
  const finalOwner = await resolveFinanceOwner(req.user, owner_id, req.params.id);

  const { rows } = await db.query(
    "INSERT INTO expenses (project_id, category, amount, note, owner_id) VALUES ($1,$2,$3,$4,$5) RETURNING *",
    [req.params.id, category, amt, note || null, finalOwner]
  );
  if (String(finalOwner) !== String(await financeOwnerId(req.user))) {
    push.notifyUser(finalOwner, "Size bir gider atandı", `${req.user.name || "Bir kullanıcı"}: ${category} — ${amt} ₺`, "/finans");
  }
  res.status(201).json(rows[0]);
});

/** Projenin temel bilgilerini düzenle (müşteri adı, hizmet türü, not, adres, lat/lng) */
router.patch("/:id", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  if (!(await checkProjectAccess(req, res, req.params.id))) return;
  const { customer_name, service, notes } = req.body;
  const geo = parseGeoFields(req.body);
  if (geo.error) return res.status(400).json({ error: geo.error });
  const sets = []; const params = []; let i = 1;
  if (customer_name !== undefined) { sets.push(`customer_name = $${i++}`); params.push(customer_name); }
  if (service !== undefined) { sets.push(`service = $${i++}`); params.push(service); }
  if (notes !== undefined) { sets.push(`notes = $${i++}`); params.push(notes); }
  i = pushGeoSets(geo.fields, sets, params, i);
  if (sets.length === 0) return res.status(400).json({ error: "Güncellenecek alan yok." });
  params.push(req.params.id);

  const { rows } = await db.query(`UPDATE projects SET ${sets.join(", ")} WHERE id = $${i} RETURNING *`, params);
  logActivity("project", req.params.id, req.user.id, "duzenlendi", null);
  res.json(rows[0]);
});

/** Projeyi sil (sadece yönetici — geri alınamaz). Bağlı görev/ödeme/gider kayıtları
 *  otomatik silinir (CASCADE); galeri fotoğrafı ve randevu geçmişi de burada temizlenir. */
router.delete("/:id", requireAuth, requireRole("admin"), async (req, res) => {
  const id = req.params.id;
  await db.query("DELETE FROM gallery WHERE project_id = $1", [id]);
  await db.query("DELETE FROM appointments WHERE project_id = $1", [id]);
  await db.query("DELETE FROM projects WHERE id = $1", [id]);
  res.json({ message: "Proje silindi." });
});

module.exports = router;
