/**
 * KDV dönem özeti — SAF fonksiyonlar (kuruş tamsayısı). TAHMİNİ/izleme amaçlıdır; beyan sorumluluğu mali müşavirdedir.
 *
 *   hesaplanan  = giden faturalarda KDV − tevkifat   (tevkifat kısmını alıcı KDV-2 ile beyan/öder → satıcının ödeyeceği KDV'den düşer)
 *   indirilecek = gelen faturalarda KDV (yalnız kdv_indirilebilir = true olanlar; indirilemeyenler ayrıca raporlanır)
 *   net         = hesaplanan − indirilecek − önceki dönemden devreden
 *   ödenecek    = max(net, 0);  devreden (sonraki döneme) = max(−net, 0)
 *   kdv2        = gelen faturalarda tevkifat (alıcı olarak sorumlu sıfatıyla KDV-2 ile ayrıca beyan/ödenir; KDV-1 ödenecek tutarına KATILMAZ)
 * Tevkifatlı işlemlerin beyanname satırlarına eşleştirilmesi mali müşavire teyit gerektirir (araştırma §1.2).
 * Taslak ve iptal faturalar hesaba katılmaz.
 */
const { addMonths, daysInMonth, fmt, pad } = require("./dates");

const COUNTED_STATUSES = ["kesildi", "gonderildi", "odendi"];

/** 'YYYY-MM' (aylık) ya da 'YYYY-Qn' (3 aylık) → {key, type, year, startMonth, endMonth, startsOn, endsOn} | null */
function parsePeriodKey(key) {
  if (typeof key !== "string") return null;
  let m = /^(\d{4})-(0[1-9]|1[0-2])$/.exec(key);
  if (m) {
    const y = +m[1], mo = +m[2];
    return { key, type: "aylik", year: y, startMonth: mo, endMonth: mo, startsOn: fmt(y, mo, 1), endsOn: fmt(y, mo, daysInMonth(y, mo)) };
  }
  m = /^(\d{4})-Q([1-4])$/.exec(key);
  if (m) {
    const y = +m[1], q = +m[2], sm = (q - 1) * 3 + 1, em = sm + 2;
    return { key, type: "uc_aylik", year: y, startMonth: sm, endMonth: em, startsOn: fmt(y, sm, 1), endsOn: fmt(y, em, daysInMonth(y, em)) };
  }
  return null;
}
const periodKeyOf = (type, year, month) => (type === "uc_aylik" ? `${year}-Q${Math.ceil(month / 3)}` : `${year}-${pad(month)}`);
/** Bir takvim tarihinin ("YYYY-MM-DD") dönemi */
const periodOfDate = (type, dateStr) => periodKeyOf(type, +dateStr.slice(0, 4), +dateStr.slice(5, 7));

function previousPeriodKey(key) {
  const p = parsePeriodKey(key);
  const prev = addMonths(p.year, p.startMonth, p.type === "uc_aylik" ? -3 : -1);
  return periodKeyOf(p.type, prev.y, prev.m);
}
function nextPeriodKey(key) {
  const p = parsePeriodKey(key);
  const nx = addMonths(p.year, p.startMonth, p.type === "uc_aylik" ? 3 : 1);
  return periodKeyOf(p.type, nx.y, nx.m);
}

/** Dönemdeki faturaları özetle. invoices: {direction,status,kdv_oran,matrah_kurus,kdv_kurus,tevkifat_kurus,tutar_kurus,kdv_indirilebilir} */
function summarizeInvoices(invoices) {
  const s = {
    hesaplananToplamKurus: 0, tevkifatGidenKurus: 0, hesaplananKurus: 0,
    indirilecekKurus: 0, indirilemeyenKurus: 0, kdv2Kurus: 0,
    gidenMatrahKurus: 0, gelenMatrahKurus: 0, counts: { giden: 0, gelen: 0 },
    byRate: { giden: {}, gelen: {} },
  };
  for (const inv of invoices) {
    if (!COUNTED_STATUSES.includes(inv.status)) continue;
    const dir = inv.direction === "giden" ? "giden" : "gelen";
    const kdv = Number(inv.kdv_kurus), mat = Number(inv.matrah_kurus), tev = Number(inv.tevkifat_kurus || 0);
    const n = Number(inv.n ?? 1); // SQL'de gruplanmış satırlar için belge adedi
    s.counts[dir] += n;
    const rk = String(Number(inv.kdv_oran));
    const b = (s.byRate[dir][rk] ||= { rate: Number(inv.kdv_oran), count: 0, matrahKurus: 0, kdvKurus: 0, tevkifatKurus: 0 });
    b.count += n; b.matrahKurus += mat; b.kdvKurus += kdv; b.tevkifatKurus += tev;
    if (dir === "giden") {
      s.gidenMatrahKurus += mat; s.hesaplananToplamKurus += kdv; s.tevkifatGidenKurus += tev; s.hesaplananKurus += kdv - tev;
    } else {
      s.gelenMatrahKurus += mat;
      if (inv.kdv_indirilebilir === false) s.indirilemeyenKurus += kdv; else s.indirilecekKurus += kdv;
      s.kdv2Kurus += tev;
    }
  }
  const list = (o) => Object.values(o).sort((a, b) => b.rate - a.rate);
  s.byRate = { giden: list(s.byRate.giden), gelen: list(s.byRate.gelen) };
  return s;
}

/** Özet + önceki devreden → dönem sonucu */
function computePeriod(summary, oncekiDevredenKurus = 0) {
  const net = summary.hesaplananKurus - summary.indirilecekKurus - oncekiDevredenKurus;
  return {
    hesaplananKurus: summary.hesaplananKurus,
    indirilecekKurus: summary.indirilecekKurus,
    oncekiDevredenKurus,
    netKurus: net,
    odenecekKurus: Math.max(net, 0),
    devredenKurus: Math.max(-net, 0),
  };
}

/**
 * Ardışık dönemleri devir zinciriyle hesapla.
 * @param {string[]} keys ardışık dönem anahtarları (eskiden yeniye)
 * @param {Object<string,Object>} summaries key → summarizeInvoices çıktısı (yoksa boş sayılır)
 * @param {number} openingCarryKurus ilk dönemin önceki devredeni
 * @param {Object<string,number>} carryOverrides key → elle girilmiş önceki devreden (varsa zincir yerine kullanılır)
 * @param {Object<string,Object>} locked key → KİLİTLİ dönemin saklanmış değerleri ({hesaplananKurus, indirilecekKurus, oncekiDevredenKurus, odenecekKurus, devredenKurus});
 *        kilitli dönem canlı hesaplanmaz, saklanan değer aynen kullanılır ve devir zincirine onun devredeni girer
 */
function chainPeriods(keys, summaries, openingCarryKurus = 0, carryOverrides = {}, locked = {}) {
  const out = []; let carry = openingCarryKurus;
  for (const key of keys) {
    const sum = summaries[key] || summarizeInvoices([]);
    let r;
    if (locked[key]) {
      const l = locked[key];
      r = { hesaplananKurus: l.hesaplananKurus, indirilecekKurus: l.indirilecekKurus, oncekiDevredenKurus: l.oncekiDevredenKurus,
            netKurus: l.hesaplananKurus - l.indirilecekKurus - l.oncekiDevredenKurus, odenecekKurus: l.odenecekKurus, devredenKurus: l.devredenKurus };
    } else {
      if (carryOverrides[key] !== undefined && carryOverrides[key] !== null) carry = carryOverrides[key];
      r = computePeriod(sum, carry);
    }
    out.push({ key, summary: sum, locked: !!locked[key], ...r });
    carry = r.devredenKurus;
  }
  return out;
}

/** Aylık dönem anahtarını (YYYY-MM) verilen tipte döneme çevirip [startKey..key] listesi üret (en çok maxBack dönem geriye) */
function keysBack(key, maxBack = 24) {
  const keys = [key];
  for (let i = 0; i < maxBack; i++) keys.unshift(previousPeriodKey(keys[0]));
  return keys;
}

module.exports = { COUNTED_STATUSES, parsePeriodKey, periodKeyOf, periodOfDate, previousPeriodKey, nextPeriodKey, summarizeInvoices, computePeriod, chainPeriods, keysBack };
