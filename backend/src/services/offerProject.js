const db = require("../db");

/**
 * Teklif "Kabul Edildi" olduğunda proje oluşturur. Tüm kabul yolları (panel, toplu durum, takip sayfası)
 * bu tek fonksiyonu kullanır; böylece sahiplik, görevler ve paylaşımlar her yerde aynı olur.
 * Aynı teklif için ikinci kez çağrılırsa mevcut projeyi döner (çift proje oluşmaz).
 */
async function createProjectFromOffer(offerId) {
  const client = await db.pool.connect();
  try {
    await client.query("BEGIN");
    // Aynı teklifin eşzamanlı kabulünü sıraya sok
    const { rows: offerRows } = await client.query("SELECT * FROM offers WHERE id = $1 FOR UPDATE", [offerId]);
    const offer = offerRows[0];
    if (!offer) { await client.query("ROLLBACK"); return null; }

    const existing = await client.query("SELECT id FROM projects WHERE offer_id = $1", [offerId]);
    if (existing.rows[0]) { await client.query("COMMIT"); return { id: existing.rows[0].id, created: false }; }

    const { rows: quoteRows } = await client.query(
      "SELECT total, items FROM quotes WHERE offer_id = $1 ORDER BY created_at DESC LIMIT 1",
      [offerId]
    );
    const { rows: seq } = await client.query("SELECT 'PRJ-' || nextval('project_code_seq') AS code");
    const { rows: proj } = await client.query(
      `INSERT INTO projects (code, offer_id, customer_name, service, total_amount, owner_id, address, lat, lng)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,
      [seq[0].code, offer.id, offer.name, offer.service, quoteRows[0]?.total || 0, offer.owner_id,
       offer.address, offer.lat, offer.lng]
    );
    const projectId = proj[0].id;

    // Teklifteki kalemler projenin Görevler listesine aktarılır
    let items = quoteRows[0]?.items;
    if (typeof items === "string") { try { items = JSON.parse(items); } catch { items = []; } }
    if (Array.isArray(items)) {
      for (const it of items) {
        const title = it.desc || it.description || "İsimsiz iş kalemi";
        await client.query(
          "INSERT INTO project_tasks (project_id, title, assigned_user_id) VALUES ($1,$2,$3)",
          [projectId, title, offer.owner_id]
        );
      }
    }

    // Teklifin paylaşıldığı kişilerle proje de paylaşılır
    await client.query(
      `INSERT INTO resource_shares (resource_type, resource_id, shared_with_user_id, shared_by_user_id)
       SELECT 'project', $1, shared_with_user_id, shared_by_user_id
       FROM resource_shares WHERE resource_type = 'offer' AND resource_id = $2
       ON CONFLICT DO NOTHING`,
      [projectId, offerId]
    );

    await client.query("COMMIT");
    return { id: projectId, created: true };
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { createProjectFromOffer };
