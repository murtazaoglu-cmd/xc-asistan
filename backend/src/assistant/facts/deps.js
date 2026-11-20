/**
 * Başka paketlerin tablolarına (invoices, vat_periods, holidays_tr, ai_actions, payment_schedule) bağımlılık YOK:
 * varlıkları ve gerekli sütunları çalışma anında yoklarız (varsayım yok). Sonuç 60 sn önbelleğe alınır.
 */
const db = require("../../db");

const cache = new Map();
const TTL = 60000;

/** has("invoices") → true/false; cols verilirse bu sütunların HEPSİ da var olmalı */
async function has(table, cols = []) {
  const key = table + "|" + cols.join(",");
  const hit = cache.get(key);
  if (hit && hit.exp > Date.now()) return hit.v;
  let v = false;
  try {
    const r = await db.query("SELECT to_regclass($1) AS t", ["public." + table]);
    if (r.rows[0].t) {
      if (cols.length === 0) v = true;
      else {
        const c = await db.query("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1", [table]);
        const have = new Set(c.rows.map((x) => x.column_name));
        v = cols.every((x) => have.has(x));
      }
    }
  } catch { v = false; }
  cache.set(key, { v, exp: Date.now() + TTL });
  return v;
}
const _reset = () => cache.clear();

/** Resmî tatil (B paketi holidays_tr varsa): "Kurban Bayramı" | null. Yarım gün (arife) iş günü sayılır → tatil değil. */
async function holidayName(dateStr) {
  if (!(await has("holidays_tr", ["day", "name"]))) return null;
  try {
    const half = await has("holidays_tr", ["half_day"]);
    const r = await db.query(`SELECT name FROM holidays_tr WHERE day = $1::date${half ? " AND half_day = false" : ""} ORDER BY name LIMIT 1`, [dateStr]);
    return r.rows[0] ? r.rows[0].name : null;
  } catch { return null; }
}

module.exports = { has, holidayName, _reset };
