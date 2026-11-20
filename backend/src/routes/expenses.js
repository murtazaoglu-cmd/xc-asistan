const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const { canAccessResource } = require("../middleware/ownership");
const { financeOwnerId, resolveFinanceOwner, canModifyFinanceRow } = require("../middleware/access");

const router = express.Router();

const SCOPES = ["ev", "dukkan", "genel"];

function validAmount(v) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/** Giderler — herkes yalnızca KENDİ defterindeki (owner_id) giderleri görür.
 *  admin/muhasebe: işletme defteri (ilk admin); ortak/personel: kendi kayıtları. */
router.get("/", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const ownerId = await financeOwnerId(req.user);
  const { rows } = await db.query(`
    SELECT e.*, p.customer_name, p.code AS project_code
    FROM expenses e
    LEFT JOIN projects p ON p.id = e.project_id
    WHERE e.owner_id = $1
    ORDER BY e.expense_date DESC
  `, [ownerId]);
  res.json(rows);
});

/** Yeni gider — project_id verilmezse genel işletme gideri olur (personel genel gider giremez) */
router.post("/", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const { category, amount, note, project_id, expense_date, scope, owner_id } = req.body;
  const amt = validAmount(amount);
  if (!category || amt === null) return res.status(400).json({ error: "Kategori ve geçerli bir tutar zorunludur." });
  if (req.user.role === "personel" && !project_id) {
    return res.status(403).json({ error: "Genel işletme gideri sadece yönetici/muhasebe tarafından girilebilir." });
  }
  if (project_id) {
    const pr = await db.query("SELECT owner_id FROM projects WHERE id = $1", [project_id]);
    if (!pr.rows[0]) return res.status(404).json({ error: "Proje bulunamadı." });
    if (!(await canAccessResource(req.user, "project", project_id, pr.rows[0].owner_id))) {
      return res.status(403).json({ error: "Bu projeye erişiminiz yok." });
    }
  }
  const validScope = SCOPES.includes(scope) ? scope : "genel";
  const finalOwner = await resolveFinanceOwner(req.user, owner_id, project_id);

  const { rows } = await db.query(
    `INSERT INTO expenses (project_id, category, amount, note, expense_date, scope, owner_id)
     VALUES ($1,$2,$3,$4,COALESCE($5, now()),$6,$7) RETURNING *`,
    [project_id || null, category, amt, note || null, expense_date || null, validScope, finalOwner]
  );
  res.status(201).json(rows[0]);
});

/** Gideri düzenle — yalnızca kendi defterindeki kayıt (admin hepsini) */
router.patch("/:id", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const existing = await db.query("SELECT owner_id, project_id FROM expenses WHERE id = $1", [req.params.id]);
  if (!existing.rows[0]) return res.status(404).json({ error: "Gider bulunamadı." });
  if (!(await canModifyFinanceRow(req.user, existing.rows[0]))) {
    return res.status(403).json({ error: "Bu gider size ait değil." });
  }

  const { category, amount, note, scope, expense_date, owner_id } = req.body;
  const sets = []; const params = []; let i = 1;
  if (category !== undefined) { sets.push(`category = $${i++}`); params.push(category); }
  if (amount !== undefined) {
    const amt = validAmount(amount);
    if (amt === null) return res.status(400).json({ error: "Geçerli bir tutar girin." });
    sets.push(`amount = $${i++}`); params.push(amt);
  }
  if (note !== undefined) { sets.push(`note = $${i++}`); params.push(note); }
  if (scope !== undefined && SCOPES.includes(scope)) { sets.push(`scope = $${i++}`); params.push(scope); }
  if (expense_date !== undefined) { sets.push(`expense_date = $${i++}`); params.push(expense_date); }
  if (owner_id !== undefined) {
    const finalOwner = await resolveFinanceOwner(req.user, owner_id, existing.rows[0].project_id);
    sets.push(`owner_id = $${i++}`); params.push(finalOwner);
  }
  if (sets.length === 0) return res.status(400).json({ error: "Güncellenecek alan yok." });
  params.push(req.params.id);
  const { rows } = await db.query(`UPDATE expenses SET ${sets.join(", ")} WHERE id = $${i} RETURNING *`, params);
  res.json(rows[0]);
});

router.delete("/:id", requireAuth, requireRole("admin","muhasebe","personel","ortak"), async (req, res) => {
  const existing = await db.query("SELECT owner_id FROM expenses WHERE id = $1", [req.params.id]);
  if (!existing.rows[0]) return res.status(404).json({ error: "Gider bulunamadı." });
  if (!(await canModifyFinanceRow(req.user, existing.rows[0]))) {
    return res.status(403).json({ error: "Bu gider size ait değil." });
  }
  await db.query("DELETE FROM expenses WHERE id = $1", [req.params.id]);
  res.json({ message: "Silindi." });
});

module.exports = router;
