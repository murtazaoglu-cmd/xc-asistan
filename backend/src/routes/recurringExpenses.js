const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const { financeOwnerId: ledgerOwner } = require("../middleware/access");

const router = express.Router();

/** "Ortak" rolü sadece kendi oluşturduğu sabit giderleri görür; admin/muhasebe için kısıtlama yok. */
/** Şu anki ay (İstanbul saatiyle) — UTC'ye göre ay başında yanlış aya düşmesin */
function currentYearMonth() {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Istanbul", year: "numeric", month: "2-digit" })
    .format(new Date()).slice(0, 7);
}
function validAmount(v) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}

router.get("/", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  const thisMonth = currentYearMonth();
  const ownerFilter = req.user.role === "ortak" ? req.user.id : null;
  const { rows } = await db.query(`
    SELECT re.*,
      EXISTS(
        SELECT 1 FROM recurring_expense_applications a
        WHERE a.recurring_expense_id = re.id AND a.year_month = $1
      ) AS applied_this_month
    FROM recurring_expenses re
    WHERE ($2::uuid IS NULL OR re.created_by = $2)
    ORDER BY re.category ASC
  `, [thisMonth, ownerFilter]);
  res.json(rows);
});

router.post("/", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  const { category, amount, note, scope } = req.body;
  const amt = validAmount(amount);
  if (!category || amt === null) return res.status(400).json({ error: "Kategori ve geçerli bir tutar zorunludur." });
  const validScope = ["ev","dukkan","genel"].includes(scope) ? scope : "genel";
  const { rows } = await db.query(
    "INSERT INTO recurring_expenses (category, amount, note, created_by, scope) VALUES ($1,$2,$3,$4,$5) RETURNING *",
    [category, amt, note || null, req.user.id, validScope]
  );
  res.status(201).json(rows[0]);
});

async function checkRecurringOwnership(req, res) {
  if (req.user.role === "ortak") {
    const existing = await db.query("SELECT created_by FROM recurring_expenses WHERE id = $1", [req.params.id]);
    if (!existing.rows[0]) { res.status(404).json({ error: "Sabit gider bulunamadı." }); return false; }
    if (String(existing.rows[0].created_by) !== String(req.user.id)) {
      res.status(403).json({ error: "Bu sabit gider size ait değil." });
      return false;
    }
  }
  return true;
}

router.patch("/:id", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  if (!(await checkRecurringOwnership(req, res))) return;
  const { category, amount, note, active, scope } = req.body;
  const sets = []; const params = []; let i = 1;
  if (category !== undefined) { sets.push(`category = $${i++}`); params.push(category); }
  if (amount !== undefined) {
    const amt = validAmount(amount);
    if (amt === null) return res.status(400).json({ error: "Geçerli bir tutar girin." });
    sets.push(`amount = $${i++}`); params.push(amt);
  }
  if (note !== undefined) { sets.push(`note = $${i++}`); params.push(note); }
  if (active !== undefined) { sets.push(`active = $${i++}`); params.push(active); }
  if (scope !== undefined && ["ev","dukkan","genel"].includes(scope)) { sets.push(`scope = $${i++}`); params.push(scope); }
  if (sets.length === 0) return res.status(400).json({ error: "Güncellenecek alan yok." });
  params.push(req.params.id);
  const { rows } = await db.query(`UPDATE recurring_expenses SET ${sets.join(", ")} WHERE id = $${i} RETURNING *`, params);
  res.json(rows[0]);
});

router.delete("/:id", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  if (!(await checkRecurringOwnership(req, res))) return;
  await db.query("DELETE FROM recurring_expenses WHERE id = $1", [req.params.id]);
  res.json({ message: "Silindi." });
});

/** Bu ayın gerçek gider kaydını oluştur — tek işlemde, çift tıklamada bile ay başına en fazla bir kez */
router.post("/:id/apply", requireAuth, requireRole("admin","muhasebe","ortak"), async (req, res) => {
  if (!(await checkRecurringOwnership(req, res))) return;
  const yearMonth = currentYearMonth();
  const recurring = await db.query("SELECT * FROM recurring_expenses WHERE id = $1", [req.params.id]);
  if (!recurring.rows[0]) return res.status(404).json({ error: "Sabit gider bulunamadı." });
  const r = recurring.rows[0];
  if (r.active === false) return res.status(400).json({ error: "Bu sabit gider pasif." });

  const client = await db.pool.connect();
  try {
    await client.query("BEGIN");
    const claim = await client.query(
      `INSERT INTO recurring_expense_applications (recurring_expense_id, year_month)
       VALUES ($1,$2) ON CONFLICT DO NOTHING RETURNING id`,
      [req.params.id, yearMonth]
    );
    if (!claim.rows[0]) {
      await client.query("ROLLBACK");
      return res.status(409).json({ error: "Bu ay için zaten eklenmiş." });
    }
    // Giderin düştüğü defter: ortak kendi sabit giderini kendi defterine, admin/muhasebe işletme defterine yazar
    const owner = req.user.role === "ortak" ? r.created_by || req.user.id : await ledgerOwner(req.user);
    const expenseRes = await client.query(
      "INSERT INTO expenses (project_id, category, amount, note, scope, owner_id) VALUES (NULL,$1,$2,$3,$4,$5) RETURNING *",
      [r.category, r.amount, r.note, r.scope || "genel", owner]
    );
    await client.query("UPDATE recurring_expense_applications SET expense_id = $1 WHERE id = $2", [expenseRes.rows[0].id, claim.rows[0].id]);
    await client.query("COMMIT");
    res.status(201).json(expenseRes.rows[0]);
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
});

module.exports = router;
