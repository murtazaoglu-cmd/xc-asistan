const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const { scopeClause } = require("../middleware/ownership");
const { financeOwnerId: resolveLedgerOwner } = require("../middleware/access");
const { listAppointments } = require("../services/appointmentQueries");
const { financeSummary } = require("../services/finance");

const router = express.Router();

/**
 * Panel girişinde ihtiyaç duyulan tüm veriyi TEK istekte döner.
 * Önceden 10 ayrı istek atılıyordu — her biri kendi network round-trip'ini
 * taşıdığı için (özellikle uzak bağlantılarda) toplam yükleme süresi
 * gereksiz uzuyordu. Burada tüm sorgular sunucu içinde paralel (Promise.all)
 * çalıştırılıp tek bir JSON'da birleştiriliyor.
 *
 * "personel" rolündeki kullanıcılar sadece kendi oluşturdukları ya da
 * kendileriyle paylaşılan teklif/proje verilerini görür.
 *
 * "saha" rolü: yalnızca kendisine atanmış/paylaşılmış randevu ve projeler ile ilgili müşteri
 * adı/telefonu/adresi döner. Finans verisi (ödeme, gider, sabit gider, sözleşme tutarı, teklif şablonu,
 * finans özeti) ASLA dönmez — bu alanlar boş dizi/null olur, sorguları hiç çalıştırılmaz.
 */
router.get("/", requireAuth, requireRole("admin", "muhasebe", "personel", "ortak", "saha"), async (req, res) => {
  try {
    const isField = req.user.role === "saha";
    const isAdmin = req.user.role === "admin";
    const isScoped = req.user.role === "personel" || req.user.role === "ortak" || isField;
    const EMPTY = { rows: [] };

    // "Ortak proje, ayrı firma" modeli: gider/ödeme kayıtları artık kime ait olduğuna göre
    // (owner_id) filtrelenir — admin dahil, herkes SADECE kendi finans payını görür.
    // muhasebe, işletme sahibinin (ilk admin) finans verisini yönetir.
    const financeOwnerId = await resolveLedgerOwner(req.user);

    const offerScope = scopeClause(req.user, "o", "offer", 1);
    const projectScope = scopeClause(req.user, "p", "project", 1);

    const queries = [
      // saha: yalnız saha için güvenli (finans/izleme kodu içermeyen) sütunlar
      db.query(isField
        ? `SELECT o.id, o.code, o.name, o.phone, o.service, o.region, o.address, o.lat, o.lng, o.status, o.message,
                  o.owner_id, o.created_at, o.updated_at
           FROM offers o WHERE 1=1 ${offerScope.clause} ORDER BY o.created_at DESC`
        : `SELECT * FROM offers o WHERE 1=1 ${offerScope.clause} ORDER BY o.created_at DESC`, offerScope.params),
      db.query(isField
        ? `SELECT p.id, p.code, p.offer_id, p.customer_name, p.service, p.stage, p.assigned_team, p.start_date, p.end_date,
                  p.notes, p.address, p.lat, p.lng, p.owner_id, o.name AS offer_customer_name, o.phone AS customer_phone
           FROM projects p LEFT JOIN offers o ON o.id = p.offer_id WHERE 1=1 ${projectScope.clause} ORDER BY p.start_date DESC`
        : `SELECT p.*, o.name AS offer_customer_name FROM projects p
           LEFT JOIN offers o ON o.id = p.offer_id WHERE 1=1 ${projectScope.clause} ORDER BY p.start_date DESC`, projectScope.params),
      isField ? Promise.resolve(EMPTY) : db.query(`
        SELECT pay.* FROM payments pay
        JOIN projects p ON p.id = pay.project_id WHERE pay.owner_id = $1 ${scopeClause(req.user, "p", "project", 2).clause}
        ORDER BY pay.paid_at DESC
      `, [financeOwnerId, ...scopeClause(req.user, "p", "project", 2).params]),
      listAppointments(req.user).then((rows) => ({ rows })),
      isField ? Promise.resolve(EMPTY) : db.query(`
        SELECT e.*, p.customer_name, p.code AS project_code
        FROM expenses e LEFT JOIN projects p ON p.id = e.project_id
        WHERE e.owner_id = $1
        ORDER BY e.expense_date DESC
      `, [financeOwnerId]),
      // saha: müşteri listesi aşağıda (JS'te) teklif/proje/randevulardan türetilir — SQL gerekmez
      isField ? Promise.resolve(EMPTY) : isScoped ? db.query(`
        WITH offer_phone AS (
          SELECT id, regexp_replace(phone, '[^0-9]', '', 'g') AS phone_key FROM offers
          WHERE owner_id = $1 OR id IN (SELECT resource_id FROM resource_shares WHERE resource_type='offer' AND shared_with_user_id = $1)
        ),
        offer_customers AS (
          SELECT op.phone_key,
            (array_agg(o.name ORDER BY o.created_at DESC))[1] AS name,
            (array_agg(o.email ORDER BY o.created_at DESC))[1] AS email,
            (array_agg(o.phone ORDER BY o.created_at DESC))[1] AS phone,
            (array_agg(o.region ORDER BY o.created_at DESC))[1] AS region,
            (array_agg(o.address ORDER BY o.created_at DESC) FILTER (WHERE o.address IS NOT NULL OR o.lat IS NOT NULL))[1] AS address,
            (array_agg(o.lat ORDER BY o.created_at DESC) FILTER (WHERE o.address IS NOT NULL OR o.lat IS NOT NULL))[1] AS lat,
            (array_agg(o.lng ORDER BY o.created_at DESC) FILTER (WHERE o.address IS NOT NULL OR o.lat IS NOT NULL))[1] AS lng,
            COUNT(*) AS offer_count, MIN(o.created_at) AS first_contact, MAX(o.created_at) AS last_contact
          FROM offers o JOIN offer_phone op ON op.id = o.id GROUP BY op.phone_key
        )
        SELECT phone_key, name, email, phone, region, address, lat, lng, offer_count, first_contact, last_contact,
          0 AS project_count, 0 AS total_contracted, 0 AS total_paid
        FROM (
          SELECT * FROM offer_customers
          UNION ALL
          SELECT regexp_replace(c.phone, '[^0-9]', '', 'g'), c.name, c.email, c.phone, c.region, c.address, c.lat, c.lng, 0,
                 c.created_at, c.created_at
          FROM customers c
          WHERE c.owner_id = $1
            AND NOT EXISTS (SELECT 1 FROM offer_customers oc WHERE oc.phone_key = regexp_replace(c.phone, '[^0-9]', '', 'g'))
        ) allc ORDER BY last_contact DESC
      `, [req.user.id]) : db.query(`
        WITH offer_phone AS (
          SELECT id, regexp_replace(phone, '[^0-9]', '', 'g') AS phone_key FROM offers
        ),
        project_paid AS (
          SELECT project_id, COALESCE(SUM(amount),0) AS paid FROM payments WHERE owner_id = $1 GROUP BY project_id
        ),
        projects_with_phone AS (
          SELECT pr.id, pr.total_amount, COALESCE(pp.paid,0) AS paid, op.phone_key
          FROM projects pr JOIN offer_phone op ON op.id = pr.offer_id
          LEFT JOIN project_paid pp ON pp.project_id = pr.id
        ),
        project_totals AS (
          SELECT phone_key, COUNT(*) AS project_count,
            COALESCE(SUM(total_amount),0) AS total_contracted,
            COALESCE(SUM(paid),0) AS total_paid
          FROM projects_with_phone GROUP BY phone_key
        ),
        offer_customers AS (
          SELECT op.phone_key,
            (array_agg(o.name ORDER BY o.created_at DESC))[1] AS name,
            (array_agg(o.email ORDER BY o.created_at DESC))[1] AS email,
            (array_agg(o.phone ORDER BY o.created_at DESC))[1] AS phone,
            (array_agg(o.region ORDER BY o.created_at DESC))[1] AS region,
            (array_agg(o.address ORDER BY o.created_at DESC) FILTER (WHERE o.address IS NOT NULL OR o.lat IS NOT NULL))[1] AS address,
            (array_agg(o.lat ORDER BY o.created_at DESC) FILTER (WHERE o.address IS NOT NULL OR o.lat IS NOT NULL))[1] AS lat,
            (array_agg(o.lng ORDER BY o.created_at DESC) FILTER (WHERE o.address IS NOT NULL OR o.lat IS NOT NULL))[1] AS lng,
            COUNT(*) AS offer_count, MIN(o.created_at) AS first_contact, MAX(o.created_at) AS last_contact
          FROM offers o JOIN offer_phone op ON op.id = o.id GROUP BY op.phone_key
        ),
        manual_customers AS (
          SELECT regexp_replace(phone, '[^0-9]', '', 'g') AS phone_key,
            name, email, phone, region, address, lat, lng, 0 AS offer_count, created_at AS first_contact, created_at AS last_contact
          FROM customers
        ),
        all_customers AS (
          SELECT * FROM offer_customers
          UNION ALL
          SELECT mc.phone_key, mc.name, mc.email, mc.phone, mc.region, mc.address, mc.lat, mc.lng, mc.offer_count, mc.first_contact, mc.last_contact
          FROM manual_customers mc
          WHERE NOT EXISTS (SELECT 1 FROM offer_customers oc WHERE oc.phone_key = mc.phone_key)
        )
        SELECT ac.phone_key, ac.name, ac.email, ac.phone, ac.region, ac.address, ac.lat, ac.lng,
          ac.offer_count, ac.first_contact, ac.last_contact,
          COALESCE(pt.project_count,0) AS project_count,
          COALESCE(pt.total_contracted,0) AS total_contracted,
          COALESCE(pt.total_paid,0) AS total_paid
        FROM all_customers ac LEFT JOIN project_totals pt ON pt.phone_key = ac.phone_key
        ORDER BY ac.last_contact DESC
      `, [financeOwnerId]),
      db.query(`
        SELECT r.*, p.customer_name, p.service AS project_service, p.code AS project_code
        FROM reminders r LEFT JOIN projects p ON p.id = r.project_id
        WHERE ($2::boolean OR r.owner_id = $1
           OR (p.id IS NOT NULL AND (p.owner_id = $1 OR p.id IN (
                SELECT resource_id FROM resource_shares WHERE resource_type = 'project' AND shared_with_user_id = $1))))
        ORDER BY r.remind_at ASC
      `, [req.user.id, isAdmin || req.user.role === "muhasebe"]),
      // Kullanıcı listesi (paylaşım/atama seçicisi): admin hepsi; muhasebe ad/rol; ortak kendi ekibi;
      // personel/saha kendi ekibi (aynı kişiyi oluşturanın ekibi + oluşturan)
      isAdmin ? db.query("SELECT id, name, email, role, created_at FROM users ORDER BY created_at DESC")
        : req.user.role === "muhasebe" ? db.query("SELECT id, name, role FROM users WHERE id != $1 ORDER BY name ASC", [req.user.id])
        : req.user.role === "ortak" ? db.query("SELECT id, name, role FROM users WHERE created_by = $1 ORDER BY name ASC", [req.user.id])
        : db.query(`
            SELECT u.id, u.name, u.role FROM users u, (SELECT created_by FROM users WHERE id = $1) me
            WHERE u.id != $1 AND me.created_by IS NOT NULL
              AND (u.created_by = me.created_by OR u.id = me.created_by)
            ORDER BY u.name ASC`, [req.user.id]),
      (isAdmin || req.user.role === "muhasebe")
        ? db.query("SELECT * FROM quote_templates ORDER BY created_at DESC")
        : Promise.resolve({ rows: [] }),
      db.query(
        `SELECT * FROM materials WHERE
           ($1 = 'admin' OR $1 = 'muhasebe'
            OR owner_id = (CASE WHEN $1 = 'ortak' THEN $2::uuid ELSE (SELECT created_by FROM users WHERE id = $2::uuid) END))
         ORDER BY name ASC`,
        [req.user.role, req.user.id]
      ),
      (isAdmin || req.user.role === "muhasebe") ? db.query(`
        SELECT re.*,
          EXISTS(SELECT 1 FROM recurring_expense_applications a WHERE a.recurring_expense_id = re.id AND a.year_month = to_char(now(),'YYYY-MM')) AS applied_this_month
        FROM recurring_expenses re ORDER BY re.category ASC
      `) : req.user.role === "ortak" ? db.query(`
        SELECT re.*,
          EXISTS(SELECT 1 FROM recurring_expense_applications a WHERE a.recurring_expense_id = re.id AND a.year_month = to_char(now(),'YYYY-MM')) AS applied_this_month
        FROM recurring_expenses re WHERE re.created_by = $1 ORDER BY re.category ASC
      `, [req.user.id]) : Promise.resolve({ rows: [] }),
    ];

    const [
      offers, projects, payments, appointments, expenses,
      customers, reminders, users, quoteTemplates, materials, recurringExpenses,
    ] = await Promise.all(queries);

    // saha: müşteri listesi yalnız erişebildiği teklif/proje/randevulardan (ad, telefon, adres) türetilir
    let customerRows = customers.rows;
    if (isField) {
      const byKey = new Map();
      const add = (name, phone, region, address, lat, lng) => {
        const key = String(phone || "").replace(/\D/g, "");
        if (!key || byKey.has(key)) return;
        byKey.set(key, { phone_key: key, name, phone, region: region || null, address: address || null, lat: lat ?? null, lng: lng ?? null });
      };
      appointments.rows.forEach((a) => add(a.customer_name, a.customer_phone, null, a.address, a.lat, a.lng));
      offers.rows.forEach((o) => add(o.name, o.phone, o.region, o.address, o.lat, o.lng));
      projects.rows.forEach((p) => add(p.offer_customer_name || p.customer_name, p.customer_phone, null, p.address, p.lat, p.lng));
      customerRows = [...byKey.values()];
    }

    res.json({
      offers: offers.rows,
      projects: projects.rows,
      payments: payments.rows,
      appointments: appointments.rows,
      expenses: expenses.rows,
      customers: customerRows,
      reminders: reminders.rows,
      users: users.rows,
      quoteTemplates: quoteTemplates.rows,
      materials: materials.rows,
      recurringExpenses: recurringExpenses.rows,
      // Kendi defterinin özeti; "ev" giderleri işletme net kârına dahil değildir (ayrı alan). saha: null
      financeSummary: isField ? null : await financeSummary(financeOwnerId),
    });
  } catch (err) {
    console.error("GET /dashboard-init hatası:", require("../services/logging").describeErrorForLog(err));
    res.status(500).json({ error: "Panel verisi alınamadı." });
  }
});

module.exports = router;
