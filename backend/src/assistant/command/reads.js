/**
 * Komut çubuğu OKUMA cevapları (R0): yetki kapsamıyla sayı/liste döner. Tüm para hesapları KURUŞ (bigint) üzerinden SQL'de yapılır;
 * metin bu sonuçlardan koddaki şablonlarla kurulur (sayı denetçisi gerekmez).
 * Kapsam mevcut uçlarla aynıdır: randevular appointmentScope, finans defteri financeOwnerId, projeler scopeClause.
 */
const db = require("../../db");
const { listAppointments } = require("../../services/appointmentQueries");
const { financeOwnerId } = require("../../middleware/access");
const { scopeClause } = require("../../middleware/ownership");
const { tail10 } = require("./scope");
const { fmtDate, fmtDateShort, istParts, kurus, DAYS } = require("./render");

const CANCELLED = "COALESCE(a.status,'') NOT ILIKE 'iptal%'";

function periodLabel(per, from, to, today) {
  switch (per) {
    case "today": return "Bugün";
    case "day": return fmtDate(from, today);
    case "week": return "Bu hafta";
    case "next_week": return "Gelecek hafta";
    case "last_week": return "Geçen hafta";
    case "month": return "Bu ay";
    case "last_month": return "Geçen ay";
    case "next_month": return "Gelecek ay";
    case "month_named": { const m = fmtDate(from, today).split(" ")[2]; return `${m} ayı`; }
    case "year": return "Bu yıl";
    case "last_year": return "Geçen yıl";
    case "upcoming": return "Yaklaşan";
    default: return `${fmtDateShort(from)} – ${fmtDateShort(to)}`;
  }
}

function apptItem(a, today, withDate) {
  const p = istParts(a.scheduled_at);
  return { id: a.id, date: p.date, time: p.time, type: a.type, status: a.status, customer_name: a.customer_name || null, customer_phone: a.customer_phone || null, address: a.address || null, service: a.service || null,
    line: `${withDate ? fmtDateShort(p.date) + " " : ""}${p.time} · ${a.customer_name || "—"} · ${a.type}` };
}

/** Müşterinin projeleri (kullanıcının kapsamında): telefon (offers.phone) veya müşteri adı eşleşmesi */
async function customerProjects(user, cust, client = db) {
  if (!cust) return [];
  const params = [await financeOwnerId(user)];
  const sc = scopeClause(user, "p", "project", 2);
  params.push(...sc.params);
  const kIdx = params.push(cust.key || tail10(cust.phone) || "-");
  const nIdx = params.push(String(cust.name || "").toLowerCase());
  const { rows } = await client.query(
    `SELECT p.id, p.code, p.service, p.customer_name, p.stage, p.total_amount, (p.total_amount*100)::bigint AS total_kurus,
            COALESCE((SELECT SUM((pm.amount*100)::bigint) FROM payments pm WHERE pm.project_id = p.id AND pm.owner_id = $1),0)::bigint AS paid_kurus
       FROM projects p LEFT JOIN offers o ON o.id = p.offer_id
      WHERE 1=1 ${sc.clause}
        AND (right(regexp_replace(COALESCE(o.phone,''), '[^0-9]', '', 'g'), 10) = $${kIdx} OR lower(p.customer_name) = $${nIdx})
      ORDER BY p.start_date DESC LIMIT 20`, params);
  return rows;
}

async function agenda(user, p, today) {
  const from = p.from, to = p.to || null;
  const where = [`a.scheduled_at >= $1::date`, CANCELLED]; const params = [from];
  if (to) { params.push(to); where.push(`a.scheduled_at < $2::date`); }
  const rows = await listAppointments(user, { extraWhere: where, extraParams: params, limit: 200 });
  const key = p.customer && p.customer.match ? p.customer.match.key : null;
  const filtered = key ? rows.filter((a) => tail10(a.customer_phone) === key || tail10(a.offer_phone) === key) : rows;
  const multi = !to || (new Date(to) - new Date(from)) / 86400000 > 1;
  return { rows: filtered, items: filtered.map((a) => apptItem(a, today, multi)), multi };
}

async function reminders(user, from, to) {
  const params = [user.id, from]; let w = "owner_id = $1 AND status = 'bekliyor' AND remind_at >= $2::date";
  if (to) { params.push(to); w += " AND remind_at < $3::date"; }
  const { rows } = await db.query(`SELECT id, title, remind_at FROM reminders WHERE ${w} ORDER BY remind_at LIMIT 100`, params);
  return rows.map((r) => { const p = istParts(r.remind_at); return { id: r.id, title: r.title, date: p.date, time: p.time }; });
}

async function answerAgenda(user, parsed, today) {
  const p = parsed.params;
  const a = await agenda(user, p, today);
  const rem = await reminders(user, p.from, p.to);
  const label = periodLabel(p.period, p.from, p.to, today);
  const lines = [...a.items.map((x) => x.line), ...rem.map((r) => `${a.multi ? fmtDateShort(r.date) + " " : ""}${r.time} · Hatırlatma: ${r.title}`)];
  const text = a.items.length + rem.length === 0
    ? `${label} için kayıtlı randevu ya da hatırlatma yok.`
    : `${label}: ${a.items.length} randevu, ${rem.length} hatırlatma.`;
  return { text, data: { period: p.period, from: p.from, to: p.to, appointments: a.items, reminders: rem, lines } };
}

async function answerAppointments(user, parsed, today) {
  const p = parsed.params;
  const a = await agenda(user, p, today);
  const label = periodLabel(p.period, p.from, p.to, today);
  const who = p.customer && p.customer.match ? ` (${p.customer.match.name})` : "";
  const text = a.items.length ? `${label}${who}: ${a.items.length} randevu var.` : `${label}${who} için randevu yok.`;
  return { text, data: { period: p.period, from: p.from, to: p.to, appointments: a.items, lines: a.items.map((x) => x.line) } };
}

/** Finans satırı filtresi: kullanıcının defteri + dönem (+ müşteri projeleri) */
async function ledgerWhere(user, p, table, dateCol, cust) {
  const params = [await financeOwnerId(user), p.from];
  let w = `x.owner_id = $1 AND x.${dateCol} >= $2::date`;
  if (p.to) { params.push(p.to); w += ` AND x.${dateCol} < $${params.length}::date`; }
  if (cust) {
    const ids = (await customerProjects(user, cust)).map((r) => r.id);
    params.push(ids); w += ` AND x.project_id = ANY($${params.length}::uuid[])`;
  }
  return { w, params };
}

async function answerCollections(user, parsed, today) {
  const p = parsed.params;
  const cust = p.customer && p.customer.match ? p.customer.match : null;
  const { w, params } = await ledgerWhere(user, p, "payments", "paid_at", cust);
  const { rows } = await db.query(`SELECT x.method, SUM((x.amount*100)::bigint)::bigint AS kurus, COUNT(*)::int AS n FROM payments x WHERE ${w} GROUP BY x.method ORDER BY 2 DESC`, params);
  const total = rows.reduce((s, r) => s + Number(r.kurus), 0);
  const count = rows.reduce((s, r) => s + r.n, 0);
  const label = periodLabel(p.period, p.from, p.to, today);
  const text = count ? `${label} toplam tahsilat ${kurus(total)} (${count} ödeme).` : `${label} kayıtlı tahsilat yok.`;
  return { text, data: { period: p.period, from: p.from, to: p.to, total_kurus: total, count, by_method: rows.map((r) => ({ method: r.method, kurus: Number(r.kurus), count: r.n })) } };
}

async function answerExpenses(user, parsed, today) {
  const p = parsed.params;
  const { w, params } = await ledgerWhere(user, p, "expenses", "expense_date", null);
  const { rows } = await db.query(`SELECT x.scope, SUM((x.amount*100)::bigint)::bigint AS kurus, COUNT(*)::int AS n FROM expenses x WHERE ${w} GROUP BY x.scope ORDER BY 2 DESC`, params);
  const total = rows.reduce((s, r) => s + Number(r.kurus), 0);
  const count = rows.reduce((s, r) => s + r.n, 0);
  const top = await db.query(`SELECT x.category, SUM((x.amount*100)::bigint)::bigint AS kurus FROM expenses x WHERE ${w} GROUP BY x.category ORDER BY 2 DESC LIMIT 5`, params);
  const label = periodLabel(p.period, p.from, p.to, today);
  const text = count ? `${label} toplam gider ${kurus(total)} (${count} kayıt).` : `${label} kayıtlı gider yok.`;
  return { text, data: { period: p.period, from: p.from, to: p.to, total_kurus: total, count, by_scope: rows.map((r) => ({ scope: r.scope, kurus: Number(r.kurus), count: r.n })), top_categories: top.rows.map((r) => ({ category: r.category, kurus: Number(r.kurus) })) } };
}

/** Alacaklar: proje toplamı − çağıranın defterindeki tahsilat > 0; müşteri (telefon/ad) bazında toplanır */
async function answerReceivables(user, parsed) {
  const params = [await financeOwnerId(user)];
  const sc = scopeClause(user, "p", "project", 2); params.push(...sc.params);
  const { rows } = await db.query(
    `SELECT p.id, p.code, p.customer_name, p.service,
            right(regexp_replace(COALESCE(o.phone,''), '[^0-9]', '', 'g'), 10) AS pk,
            (p.total_amount*100)::bigint AS total_kurus,
            COALESCE((SELECT SUM((pm.amount*100)::bigint) FROM payments pm WHERE pm.project_id = p.id AND pm.owner_id = $1),0)::bigint AS paid_kurus
       FROM projects p LEFT JOIN offers o ON o.id = p.offer_id WHERE 1=1 ${sc.clause}`, params);
  const want = parsed.params.customer && parsed.params.customer.match ? parsed.params.customer.match : null;
  const by = new Map();
  for (const r of rows) {
    const rem = Number(r.total_kurus) - Number(r.paid_kurus);
    if (rem <= 0) continue;
    if (want && !(r.pk && r.pk === want.key) && String(r.customer_name).toLowerCase() !== String(want.name).toLowerCase()) continue;
    const k = r.pk || "n:" + String(r.customer_name).toLowerCase();
    const cur = by.get(k) || { customer_name: r.customer_name, key: r.pk || null, remaining_kurus: 0, projects: [] };
    cur.remaining_kurus += rem;
    cur.projects.push({ id: r.id, code: r.code, service: r.service, remaining_kurus: rem });
    by.set(k, cur);
  }
  const list = [...by.values()].sort((a, b) => b.remaining_kurus - a.remaining_kurus);
  const total = list.reduce((s, x) => s + x.remaining_kurus, 0);
  const top = list.slice(0, 20);
  const text = list.length ? `Toplam alacak ${kurus(total)}; ${list.length} müşteriden bekleniyor. En büyük: ${top[0].customer_name} (${kurus(top[0].remaining_kurus)}).` : "Açık alacak görünmüyor.";
  return { text, data: { total_kurus: total, customer_count: list.length, items: top.map((x) => ({ ...x, line: `${x.customer_name} · ${kurus(x.remaining_kurus)}` })) } };
}

function answerCustomerSearch(parsed) {
  const p = parsed.params;
  const list = (p.matches && p.matches.length ? p.matches : (p.customer && p.customer.match ? [p.customer.match] : [])).slice(0, 10);
  const items = list.map((c) => ({ key: c.key, name: c.name, phone: c.phone || null, line: `${c.name}${c.phone ? " · " + c.phone : ""}` }));
  const text = items.length ? `${items.length} müşteri bulundu.` : "Eşleşen müşteri bulunamadı.";
  return { text, data: { query: p.query || null, items } };
}

module.exports = { answerAgenda, answerAppointments, answerCollections, answerExpenses, answerReceivables, answerCustomerSearch, customerProjects, periodLabel, agenda };
