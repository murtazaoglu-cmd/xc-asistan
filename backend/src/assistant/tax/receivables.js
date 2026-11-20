/**
 * Tahsilat (alacak) yaşlandırma ve taksit yardımcıları — SAF fonksiyonlar, kuruş tamsayısı.
 *
 * Kova kuralı (vadeden bugüne geçen gün sayısı = daysOverdue):
 *   daysOverdue ≤ 0 → "notDue" (vadesi gelmemiş / bugün vadesi dolan)
 *   1–30 → "0-30", 31–60 → "31-60", 61–90 → "61-90", ≥ 91 → "90+"
 */
const { addDays, daysBetween, addMonths, dateIn, fmt } = require("./dates");

const BUCKETS = ["notDue", "0-30", "31-60", "61-90", "90+"];

function bucketOf(daysOverdue) {
  if (daysOverdue <= 0) return "notDue";
  if (daysOverdue <= 30) return "0-30";
  if (daysOverdue <= 60) return "31-60";
  if (daysOverdue <= 90) return "61-90";
  return "90+";
}

/** Plan satırının etkin durumu: bekliyor + vadesi geçmiş → 'gecikti' */
function effectiveStatus(item, today) {
  if (item.status === "bekliyor" && String(item.due_date).slice(0, 10) < today) return "gecikti";
  return item.status;
}

/**
 * Açık alacak kalemlerini birleştir. Çift sayımı önlemek için: bir giden faturaya bağlı AKTİF (iptal olmayan)
 * taksit planı satırı varsa, o fatura ayrıca sayılmaz (taksitler faturanın yerini alır).
 * scheduleRows: {id, amount_kurus, due_date, status, project_id, offer_id, invoice_id, customer_name, kind, method}
 * invoiceRows:  {id, odenecek_kurus (=tutar−tevkifat), due_date, status, direction, counterparty, project_id}
 */
function openReceivables(scheduleRows, invoiceRows) {
  const items = [];
  const covered = new Set();
  for (const r of scheduleRows) {
    if (r.status === "iptal") continue;
    if (r.invoice_id) covered.add(String(r.invoice_id));
    if (r.status !== "bekliyor") continue;
    items.push({ source: "plan", id: r.id, amount_kurus: Number(r.amount_kurus), due_date: String(r.due_date).slice(0, 10), customer_name: r.customer_name || null, project_id: r.project_id || null, offer_id: r.offer_id || null, invoice_id: r.invoice_id || null, kind: r.kind, method: r.method || null });
  }
  for (const r of invoiceRows) {
    if (r.direction !== "giden" || !["kesildi", "gonderildi"].includes(r.status) || !r.due_date) continue; // vadesiz fatura yaşlandırılamaz
    if (covered.has(String(r.id))) continue;
    items.push({ source: "fatura", id: r.id, amount_kurus: Number(r.odenecek_kurus), due_date: String(r.due_date).slice(0, 10), customer_name: r.counterparty || null, project_id: r.project_id || null, offer_id: null, invoice_id: r.id, kind: "fatura", method: null });
  }
  return items;
}

/** Yaşlandırma: kovalar + vadesi geçen liste (en eski önce) + müşteri bazında toplam */
function buildAging(items, today) {
  const buckets = Object.fromEntries(BUCKETS.map((b) => [b, { count: 0, totalKurus: 0 }]));
  const overdue = [];
  const byCustomer = new Map();
  let total = 0, overdueTotal = 0;
  for (const it of items) {
    const daysOverdue = daysBetween(it.due_date, today);
    const bucket = bucketOf(daysOverdue);
    buckets[bucket].count++; buckets[bucket].totalKurus += it.amount_kurus;
    total += it.amount_kurus;
    const row = { ...it, days_overdue: Math.max(daysOverdue, 0), days_until_due: Math.max(-daysOverdue, 0), bucket };
    if (daysOverdue > 0) {
      overdue.push(row); overdueTotal += it.amount_kurus;
      const k = it.customer_name || "(Müşteri belirtilmemiş)";
      const c = byCustomer.get(k) || { customer_name: k, count: 0, overdueKurus: 0, oldestDaysOverdue: 0 };
      c.count++; c.overdueKurus += it.amount_kurus; c.oldestDaysOverdue = Math.max(c.oldestDaysOverdue, daysOverdue);
      byCustomer.set(k, c);
    }
  }
  overdue.sort((a, b) => b.days_overdue - a.days_overdue || b.amount_kurus - a.amount_kurus);
  return {
    asOf: today, buckets, totalKurus: total, overdueKurus: overdueTotal,
    overdueCount: overdue.length, overdueItems: overdue,
    byCustomer: [...byCustomer.values()].sort((a, b) => b.overdueKurus - a.overdueKurus),
  };
}

/**
 * Taksit planı üret: toplam `count` eşit parçaya bölünür; kuruş artığı SON taksite eklenir (toplam her zaman tutar).
 * Vade: firstDue + i ay (ay sonu sıkıştırması: 31 Ocak + 1 ay = 28/29 Şubat; gün her zaman İLK vadenin gününden hesaplanır) ya da intervalDays.
 */
function splitInstallments({ totalKurus, count, firstDue, intervalMonths = 1, intervalDays = null }) {
  if (!Number.isInteger(totalKurus) || totalKurus < 1) return { error: "Toplam tutar pozitif kuruş tamsayısı olmalıdır." };
  if (!Number.isInteger(count) || count < 1 || count > 60) return { error: "Taksit sayısı 1-60 arasında olmalıdır." };
  if (totalKurus < count) return { error: "Taksit başına en az 1 kuruş düşmelidir." };
  const base = Math.floor(totalKurus / count);
  const out = [];
  const y0 = +firstDue.slice(0, 4), m0 = +firstDue.slice(5, 7), d0 = +firstDue.slice(8, 10);
  for (let i = 0; i < count; i++) {
    const amount = i === count - 1 ? totalKurus - base * (count - 1) : base;
    let due;
    if (intervalDays) due = addDays(firstDue, intervalDays * i);
    else { const t = addMonths(y0, m0, intervalMonths * i); due = dateIn(t.y, t.m, d0); }
    out.push({ seq: i + 1, amount_kurus: amount, due_date: due });
  }
  return { items: out };
}

module.exports = { BUCKETS, bucketOf, effectiveStatus, openReceivables, buildAging, splitInstallments };
