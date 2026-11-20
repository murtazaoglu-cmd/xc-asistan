/**
 * KDV dönem hesabının VERİTABANI katmanı (saf mantık vatPeriod.js'te). Hem /api/vat uçları hem de zamanlı hatırlatma işleyicileri kullanır.
 */
const db = require("../../db");
const VP = require("./vatPeriod");
const TC = require("./taxCalendar");
const { orgIdForUser } = require("../org");

const MAX_CHAIN = 60;                        // devir zinciri için en çok geriye bakılan dönem
const RULE_KEY = { aylik: "kdv1_aylik", uc_aylik: "kdv1_uc_aylik" };

/** [firstKey .. lastKey] ardışık anahtarlar (aynı tipte) */
function keysBetween(firstKey, lastKey) {
  const keys = []; let k = firstKey;
  for (let i = 0; i < 600 && k <= lastKey; i++) { keys.push(k); k = VP.nextPeriodKey(k); }
  return keys;
}

/**
 * Bir defter için [firstKey..lastKey] dönemlerini hesapla (devir zinciriyle). Kilitli dönemler saklanan değerle gelir.
 * @returns {Promise<Array>} chainPeriods çıktısı + starts/ends + stored satırı
 */
async function computeRange(ledgerId, firstKey, lastKey) {
  const first = VP.parsePeriodKey(firstKey), last = VP.parsePeriodKey(lastKey);
  if (!first || !last || first.type !== last.type) throw new Error("Geçersiz dönem aralığı");
  const type = first.type;
  const stored = (await db.query("SELECT *, starts_on::text AS starts_on, ends_on::text AS ends_on, due_date::text AS due_date FROM vat_periods WHERE owner_id = $1 AND period_type = $2", [ledgerId, type])).rows;
  const byKey = new Map(stored.map((r) => [r.period_key, r]));

  // Zincir başlangıcı: ilk sayılan faturanın dönemi (en çok MAX_CHAIN dönem geriye); daha önce fatura yoksa devir 0'dır
  const minRow = (await db.query("SELECT MIN(issue_date)::text AS d FROM invoices WHERE owner_id = $1 AND status = ANY($2::text[])", [ledgerId, VP.COUNTED_STATUSES])).rows[0];
  let startKey = firstKey;
  if (minRow && minRow.d) {
    const minKey = VP.periodOfDate(type, minRow.d);
    if (minKey < firstKey) startKey = minKey;
  }
  let keys = keysBetween(startKey, lastKey);
  if (keys.length > MAX_CHAIN + keysBetween(firstKey, lastKey).length) keys = keys.slice(keys.length - (MAX_CHAIN + keysBetween(firstKey, lastKey).length));

  const sp = VP.parsePeriodKey(keys[0]), ep = VP.parsePeriodKey(keys[keys.length - 1]);
  const { rows } = await db.query(
    `SELECT to_char(issue_date, 'YYYY-MM') AS ym, direction, kdv_oran, kdv_indirilebilir, COUNT(*)::int AS n,
            SUM(matrah_kurus)::bigint AS matrah_kurus, SUM(kdv_kurus)::bigint AS kdv_kurus, SUM(tevkifat_kurus)::bigint AS tevkifat_kurus
       FROM invoices WHERE owner_id = $1 AND status = ANY($2::text[]) AND issue_date BETWEEN $3::date AND $4::date
      GROUP BY 1, 2, 3, 4`, [ledgerId, VP.COUNTED_STATUSES, sp.startsOn, ep.endsOn]);
  const lists = {};
  for (const r of rows) {
    const key = VP.periodOfDate(type, r.ym + "-01");
    (lists[key] ||= []).push({ direction: r.direction, status: "kesildi", kdv_oran: Number(r.kdv_oran), kdv_indirilebilir: r.kdv_indirilebilir, n: r.n, matrah_kurus: Number(r.matrah_kurus), kdv_kurus: Number(r.kdv_kurus), tevkifat_kurus: Number(r.tevkifat_kurus) });
  }
  const summaries = Object.fromEntries(Object.entries(lists).map(([k, v]) => [k, VP.summarizeInvoices(v)]));
  const overrides = {}, locked = {};
  for (const r of stored) {
    if (r.manual_carry_in_kurus !== null && r.manual_carry_in_kurus !== undefined) overrides[r.period_key] = Number(r.manual_carry_in_kurus);
    if (r.status === "kilitli") locked[r.period_key] = { hesaplananKurus: Number(r.hesaplanan_kurus), indirilecekKurus: Number(r.indirilecek_kurus), oncekiDevredenKurus: Number(r.onceki_devreden_kurus), odenecekKurus: Number(r.odenecek_kurus), devredenKurus: Number(r.devreden_kurus) };
  }
  const chain = VP.chainPeriods(keys, summaries, 0, overrides, locked);
  const wanted = new Set(keysBetween(firstKey, lastKey));
  return chain.filter((c) => wanted.has(c.key)).map((c) => ({ ...c, ...VP.parsePeriodKey(c.key), stored: byKey.get(c.key) || null }));
}

/** KDV son günü için takvim kuralı + tatiller */
async function loadDueContext(orgId, years) {
  const [items, hol] = await Promise.all([
    db.query("SELECT key, rule, verified FROM tax_calendar_items WHERE org_id = $1 AND key = ANY($2::text[])", [orgId, Object.values(RULE_KEY)]),
    db.query("SELECT day::text AS day, name, half_day, verified FROM holidays_tr WHERE org_id = $1 AND day BETWEEN $2::date AND $3::date", [orgId, `${Math.min(...years)}-01-01`, `${Math.max(...years) + 1}-12-31`]),
  ]);
  return { items: Object.fromEntries(items.rows.map((r) => [r.key, r])), holidays: hol.rows };
}

/** Dönem sonucuna son gün + teyit bayrakları ekle */
function decorate(p, due) {
  const item = due.items[RULE_KEY[p.type]];
  const d = item ? TC.vatDueDate(p.key, item.rule, due.holidays) : null;
  const reasons = ["KDV hesabı tahminidir; beyan sorumluluğu mali müşavirdedir"];
  if (!item) reasons.push("KDV son gün kuralı vergi takviminde yok");
  else if (!item.verified) reasons.push("KDV son gün kuralı (vergi takvimi kaydı) doğrulanmadı");
  if (d && d.unverifiedHoliday) reasons.push("Son gün kaydırmasında doğrulanmamış tatil günü kullanıldı");
  if (p.summary.tevkifatGidenKurus > 0 || p.summary.kdv2Kurus > 0) reasons.push("Tevkifatlı işlemlerin beyanname satırlarına eşleştirilmesi mali müşavire teyit edilmeli");
  const s = p.stored;
  return {
    period_key: p.key, period_type: p.type, year: p.year, month: p.startMonth, starts_on: p.startsOn, ends_on: p.endsOn,
    status: p.locked ? "kilitli" : "acik", locked_at: s ? s.locked_at : null,
    hesaplanan_kurus: p.hesaplananKurus, indirilecek_kurus: p.indirilecekKurus, onceki_devreden_kurus: p.oncekiDevredenKurus,
    manual_carry_in_kurus: s && s.manual_carry_in_kurus !== null ? Number(s.manual_carry_in_kurus) : null,
    net_kurus: p.netKurus, odenecek_kurus: p.odenecekKurus, devreden_kurus: p.devredenKurus,
    kdv2_kurus: p.summary.kdv2Kurus, indirilemeyen_kurus: p.summary.indirilemeyenKurus,
    hesaplanan_toplam_kurus: p.summary.hesaplananToplamKurus, tevkifat_giden_kurus: p.summary.tevkifatGidenKurus,
    belge_sayisi: p.summary.counts, oran_kirilimi: p.summary.byRate,
    due_date: d ? d.due : null, due_nominal: d ? d.nominal : null, due_shifted: d ? d.shifted : null,
    note: s ? s.note : null, stored: !!s,
    tahmini: true, needs_confirmation: true, confirmation_reasons: reasons,
  };
}

async function saveSnapshot(ledgerId, p, { lock, userId, note, manualCarry }) {
  const per = VP.parsePeriodKey(p.period_key);
  await db.query(
    `INSERT INTO vat_periods (owner_id, org_id, period_key, period_type, year, month, starts_on, ends_on, hesaplanan_kurus, indirilecek_kurus, onceki_devreden_kurus,
        manual_carry_in_kurus, odenecek_kurus, devreden_kurus, kdv2_kurus, indirilemeyen_kurus, due_date, status, locked_at, locked_by, note, computed_at)
     VALUES ($1,$21,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20, now())
     ON CONFLICT (owner_id, period_key) DO UPDATE SET
        hesaplanan_kurus = EXCLUDED.hesaplanan_kurus, indirilecek_kurus = EXCLUDED.indirilecek_kurus, onceki_devreden_kurus = EXCLUDED.onceki_devreden_kurus,
        manual_carry_in_kurus = EXCLUDED.manual_carry_in_kurus, odenecek_kurus = EXCLUDED.odenecek_kurus, devreden_kurus = EXCLUDED.devreden_kurus,
        kdv2_kurus = EXCLUDED.kdv2_kurus, indirilemeyen_kurus = EXCLUDED.indirilemeyen_kurus, due_date = EXCLUDED.due_date,
        status = EXCLUDED.status, locked_at = EXCLUDED.locked_at, locked_by = EXCLUDED.locked_by, note = EXCLUDED.note, computed_at = now()`,
    [ledgerId, p.period_key, per.type, per.year, per.startMonth, per.startsOn, per.endsOn, p.hesaplanan_kurus, p.indirilecek_kurus, p.onceki_devreden_kurus,
      manualCarry === undefined ? p.manual_carry_in_kurus : manualCarry, p.odenecek_kurus, p.devreden_kurus, p.kdv2_kurus, p.indirilemeyen_kurus, p.due_date,
      lock ? "kilitli" : "acik", lock ? new Date() : null, lock ? userId : null, note === undefined ? p.note : note, await orgIdForUser(ledgerId)]);
}

module.exports = { RULE_KEY, keysBetween, computeRange, loadDueContext, decorate, saveSnapshot };
