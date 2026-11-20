/** briefings tablosu: yazma/okuma/okundu. period_start DATE alanı to_char ile metne çevrilir (saat dilimi kayması olmasın). */
const db = require("../../db");
const clock = require("../clock");

const COLS = `id, kind, to_char(period_start,'YYYY-MM-DD') AS period_start, title, body_text, data, generated_by, generated_at, read_at`;

function present(r) {
  if (!r) return null;
  return { id: r.id, kind: r.kind, date: r.period_start, title: r.title, text: r.body_text, data: r.data, generated_by: r.generated_by, generated_at: new Date(r.generated_at).toISOString(), read_at: r.read_at ? new Date(r.read_at).toISOString() : null };
}

/** Upsert (okundu bilgisi korunur). → sunulan brifing */
async function save({ orgId, userId, kind, periodStart, title, bodyText, data, generatedBy = "job", now = clock.now() }) {
  const { rows } = await db.query(
    `INSERT INTO briefings (org_id, user_id, kind, period_start, title, body_text, data, generated_by, generated_at)
     VALUES ($1,$2,$3,$4::date,$5,$6,$7,$8,$9)
     ON CONFLICT (user_id, kind, period_start) DO UPDATE SET title = EXCLUDED.title, body_text = EXCLUDED.body_text, data = EXCLUDED.data,
       generated_by = CASE WHEN briefings.generated_by = 'job' THEN 'job' ELSE EXCLUDED.generated_by END, generated_at = EXCLUDED.generated_at
     RETURNING ${COLS}`, [orgId, userId, kind, periodStart, title.slice(0, 200), bodyText, JSON.stringify(data), generatedBy, now]);
  return present(rows[0]);
}
async function get(userId, kind, periodStart) {
  const { rows } = await db.query(`SELECT ${COLS} FROM briefings WHERE user_id = $1 AND kind = $2 AND period_start = $3::date`, [userId, kind, periodStart]);
  return present(rows[0]);
}
async function list(userId, { kind, limit = 20 } = {}) {
  const { rows } = await db.query(
    `SELECT ${COLS} FROM briefings WHERE user_id = $1 AND ($2::text IS NULL OR kind = $2) ORDER BY period_start DESC, generated_at DESC LIMIT ${Math.min(Math.max(Number(limit) || 20, 1), 100)}`, [userId, kind || null]);
  return rows.map(present);
}
async function markRead(userId, id, now = clock.now()) {
  const { rows } = await db.query(`UPDATE briefings SET read_at = COALESCE(read_at, $3) WHERE id = $1 AND user_id = $2 RETURNING ${COLS}`, [id, userId, now]);
  return present(rows[0]);
}
module.exports = { save, get, list, markRead, present, COLS };
