/**
 * Vergi takvimi motoru — SAF fonksiyonlar. Tarihler VERİDİR (tax_calendar_items / holidays_tr tabloları);
 * burada yalnızca "kural → tarih" genişletme ve hafta sonu/resmî tatil kaydırması vardır.
 * Hiçbir son gün bu dosyada sabit kodlanmamıştır; çıktı "TAHMİNİ"dir, hukuki kaynak değildir.
 *
 * Kural biçimleri (item.rule JSON):
 *   {freq:'monthly',   day:28|'last', period_offset_months:1}     her vergilendirme ayı M için M+offset ayının gününde
 *   {freq:'quarterly', day:28,        period_offset_months:1}     çeyrek sonu ayları (3,6,9,12) için
 *   {freq:'yearly',    dates:[{month:5, day:17, label:'I. dönem'}, …]}   her yıl bu ay/gün
 *   rule yoksa item.due_date tek seferlik tarihtir.
 * Kaydırma: son gün Cumartesi/Pazar ya da tam gün resmî tatilse izleyen ilk iş gününe ertelenir (araştırma §1.4 örnekleriyle uyumlu;
 * yarım gün (arife) iş günüdür). Mali tatil (1–20 Temmuz) modellenmez.
 */
const { isValidIsoDate, addDays, daysBetween, weekday, addMonths, dateIn, fmt, pad } = require("./dates");

const MONTHS_TR = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];
const monthLabel = (y, m) => `${MONTHS_TR[m - 1]} ${y}`;

/** holidays: [{day:'2026-05-27', name, half_day?, verified?}] → Map(day → kayıt) */
function holidayMap(holidays) {
  const map = new Map();
  for (const h of holidays || []) map.set(String(h.day).slice(0, 10), h);
  return map;
}

/** Tam gün resmî tatil mi? (arife yarım günü iş günü sayılır) */
const isFullHoliday = (day, hmap) => { const h = hmap.get(day); return !!h && !h.half_day; };
const isBusinessDay = (day, hmap) => { const w = weekday(day); return w !== 0 && w !== 6 && !isFullHoliday(day, hmap); };

/**
 * İzleyen ilk iş gününe kaydır.
 * @returns {{date, shifted, reasons: string[], unverifiedHoliday: boolean}}
 */
function shiftToBusinessDay(day, hmap) {
  let d = day; const reasons = new Set(); let unverifiedHoliday = false;
  for (let i = 0; i < 30 && !isBusinessDay(d, hmap); i++) {
    const w = weekday(d);
    if (w === 0 || w === 6) reasons.add("hafta_sonu");
    if (isFullHoliday(d, hmap)) { reasons.add("resmi_tatil"); if (!hmap.get(d).verified) unverifiedHoliday = true; }
    d = addDays(d, 1);
  }
  return { date: d, shifted: d !== day, reasons: [...reasons], unverifiedHoliday };
}

function validateRule(rule) {
  if (rule === null || rule === undefined) return null;
  if (typeof rule !== "object" || Array.isArray(rule)) return "Kural bir nesne olmalıdır.";
  const dayOk = (d) => d === "last" || (Number.isInteger(d) && d >= 1 && d <= 31);
  if (rule.freq === "monthly" || rule.freq === "quarterly") {
    if (!dayOk(rule.day)) return "Kuralda day 1-31 ya da 'last' olmalıdır.";
    const off = rule.period_offset_months ?? 0;
    if (!Number.isInteger(off) || off < 0 || off > 12) return "period_offset_months 0-12 arasında tamsayı olmalıdır.";
    return null;
  }
  if (rule.freq === "yearly") {
    if (!Array.isArray(rule.dates) || rule.dates.length === 0 || rule.dates.length > 24) return "yearly kuralında 1-24 adet dates gerekir.";
    for (const x of rule.dates) {
      if (!x || !Number.isInteger(x.month) || x.month < 1 || x.month > 12 || !dayOk(x.day)) return "dates öğeleri {month:1-12, day:1-31|'last'} olmalıdır.";
      if (x.label !== undefined && (typeof x.label !== "string" || x.label.length > 80)) return "dates.label en çok 80 karakter olabilir.";
    }
    return null;
  }
  return "freq 'monthly', 'quarterly' veya 'yearly' olmalıdır.";
}

/** Kural → [{periodLabel, nominal}] (nominal: kaydırma ÖNCESİ tarih) — nominal ∈ [fromNominal, toNominal] */
function nominalDates(rule, fromNominal, toNominal) {
  const out = [];
  const fy = +fromNominal.slice(0, 4), ty = +toNominal.slice(0, 4);
  if (rule.freq === "yearly") {
    for (let y = fy; y <= ty; y++) for (const x of rule.dates) {
      const nominal = dateIn(y, x.month, x.day);
      out.push({ periodLabel: x.label || `${y}`, nominal });
    }
  } else {
    const off = rule.period_offset_months ?? 0;
    // vergilendirme dönemi ayı M: nominal ay = M + off. Tarama aralığı: from'dan (off+1) ay geriye
    const start = addMonths(fy, +fromNominal.slice(5, 7), -(off + 1));
    const total = (ty * 12 + +toNominal.slice(5, 7)) - (start.y * 12 + start.m) + 2;
    for (let i = 0; i < total; i++) {
      const per = addMonths(start.y, start.m, i);
      if (rule.freq === "quarterly" && per.m % 3 !== 0) continue;
      const due = addMonths(per.y, per.m, off);
      out.push({ periodLabel: rule.freq === "quarterly" ? `${per.y} ${per.m / 3}. çeyrek (${monthLabel(per.y, per.m)} sonu)` : monthLabel(per.y, per.m), nominal: dateIn(due.y, due.m, rule.day) });
    }
  }
  return out.filter((o) => o.nominal >= fromNominal && o.nominal <= toNominal);
}

/**
 * Bir kalemin [from, to] (KAYDIRILMIŞ son gün) aralığındaki tüm oluşumları.
 * item: {key,title,kind,rule,due_date,verified,confidence,source,applies_to,enabled}
 */
function expandItem(item, from, to, hmap) {
  if (item.enabled === false) return [];
  const raw = [];
  // kaydırma en çok ~30 gün ileri atar: nominal tarama aralığını geniş tut
  const fromN = addDays(from, -31), toN = to;
  if (item.rule) {
    const err = validateRule(item.rule);
    if (err) return [];
    raw.push(...nominalDates(item.rule, fromN, toN));
  } else if (item.due_date && isValidIsoDate(String(item.due_date).slice(0, 10))) {
    raw.push({ periodLabel: item.period_label || null, nominal: String(item.due_date).slice(0, 10) });
  }
  const out = [];
  for (const r of raw) {
    // tek seferlik tarihler elle girilmiştir: kaydırma uygulanmaz (kullanıcı/mali müşavir kesin tarihi yazar)
    const sh = item.rule ? shiftToBusinessDay(r.nominal, hmap) : { date: r.nominal, shifted: false, reasons: [], unverifiedHoliday: false };
    if (sh.date < from || sh.date > to) continue;
    out.push({
      item_id: item.id || null, key: item.key, title: item.title, kind: item.kind || null,
      period_label: r.periodLabel, nominal_date: r.nominal, due_date: sh.date,
      shifted: sh.shifted, shift_reasons: sh.reasons,
      verified: !!item.verified, confidence: item.confidence || "belirsiz", source: item.source || null, applies_to: item.applies_to || "hepsi",
      // Teyit bayrağı: kayıt doğrulanmadıysa VEYA kaydırmada doğrulanmamış bir tatil günü kullanıldıysa
      needs_confirmation: !item.verified || sh.unverifiedHoliday,
      confirmation_reasons: [...(!item.verified ? ["takvim kaydı doğrulanmadı"] : []), ...(sh.unverifiedHoliday ? ["kaydırmada kullanılan tatil günü doğrulanmadı"] : [])],
    });
  }
  return out;
}

/** Tüm kalemler için oluşumlar (son güne göre sıralı). today verilirse days_until eklenir. */
function occurrences(items, { from, to, holidays, today, appliesTo } = {}) {
  const hmap = holidays instanceof Map ? holidays : holidayMap(holidays);
  let out = [];
  for (const it of items) {
    if (appliesTo && it.applies_to && it.applies_to !== "hepsi" && it.applies_to !== appliesTo) continue;
    out.push(...expandItem(it, from, to, hmap));
  }
  out.sort((a, b) => (a.due_date < b.due_date ? -1 : a.due_date > b.due_date ? 1 : a.key < b.key ? -1 : 1));
  if (today) out = out.map((o) => ({ ...o, days_until: daysBetween(today, o.due_date) }));
  return out;
}

/** Yaklaşanlar: today'den itibaren `days` gün (varsayılan 45) */
function upcoming(items, { today, days = 45, holidays, appliesTo } = {}) {
  return occurrences(items, { from: today, to: addDays(today, days), holidays, today, appliesTo });
}

/**
 * Hatırlatma planı: son günden offsets gün önce (varsayılan T−7, T−3, T−1 ve son gün) — M8 eşikleriyle uyumlu (tasarım §1.3).
 * Dönüş: bugün hatırlatılması gerekenler [{...occurrence, offset}]
 */
function remindersDue(items, { today, holidays, offsets = [7, 3, 1, 0], appliesTo } = {}) {
  const maxOff = Math.max(...offsets);
  return upcoming(items, { today, days: maxOff, holidays, appliesTo }).filter((o) => offsets.includes(o.days_until)).map((o) => ({ ...o, offset: o.days_until }));
}

/** KDV dönemi son günü: kuraldan ilgili dönem ayı için kaydırılmış son tarih (kural yoksa null) */
function vatDueDate(periodKey, rule, holidays) {
  if (!rule || validateRule(rule)) return null;
  const hmap = holidays instanceof Map ? holidays : holidayMap(holidays);
  const m = /^(\d{4})-(\d{2})$/.exec(periodKey) || null;
  const q = /^(\d{4})-Q([1-4])$/.exec(periodKey) || null;
  let y, mo;
  if (m) { y = +m[1]; mo = +m[2]; } else if (q) { y = +q[1]; mo = +q[2] * 3; } else return null;
  const off = rule.period_offset_months ?? 0;
  const due = addMonths(y, mo, off);
  const nominal = dateIn(due.y, due.m, rule.day);
  const sh = shiftToBusinessDay(nominal, hmap);
  return { nominal, due: sh.date, shifted: sh.shifted, unverifiedHoliday: sh.unverifiedHoliday };
}

module.exports = { MONTHS_TR, monthLabel, holidayMap, isBusinessDay, shiftToBusinessDay, validateRule, expandItem, occurrences, upcoming, remindersDue, vatDueDate };
