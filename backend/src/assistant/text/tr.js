/**
 * Türkçe metin yardımcıları (saf, bağımlılıksız): para, tarih, sayı+isim, ünlü uyumu ekleri, çoğul.
 * Para her yerde KURUŞ TAMSAYISIDIR; metne yalnız buradaki biçimleyiciyle çevrilir.
 *
 *   formatTL(1245000)          → "₺12.450,00"       formatTL(-5650000) → "-₺56.500,00"
 *   formatPct(1450)            → "%14,5"            (bp = baz puan: 10000 = %100)
 *   formatDate("2026-11-20")   → "20 Kas 2026"       formatDateShort → "20 Kas"
 *   weekdayName("2026-11-20")  → "Cuma"
 *   ek("Ahmet","dat",{proper:true}) → "Ahmet'e"      ek("teklif","poss") → "teklifi"
 *   countPhrase(3,"randevu")   → "3 randevu"        (Türkçede sayıdan sonra isim tekil kalır)
 */
const MONTHS = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"];
const MONTHS_LONG = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];
const WEEKDAYS = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"];

const lower = (s) => String(s == null ? "" : s).toLocaleLowerCase("tr-TR");
const upper = (s) => String(s == null ? "" : s).toLocaleUpperCase("tr-TR");
const cap = (s) => { const t = String(s == null ? "" : s); return t ? upper(t[0]) + t.slice(1) : t; };

/** Kuruş tamsayısı → "₺12.450,00" (negatif: "-₺56.500,00"). Tamsayı olmayan girdi yuvarlanır. */
function formatTL(kurus, opts = {}) {
  const k = Math.round(Number(kurus) || 0);
  const neg = k < 0;
  const abs = Math.abs(k);
  const lira = Math.floor(abs / 100), kr = abs % 100;
  const grouped = String(lira).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  const s = `₺${grouped},${String(kr).padStart(2, "0")}`;
  if (neg) return "-" + s;
  return opts.plus && k > 0 ? "+" + s : s;
}
/** Baz puan (10000 = %100) → "%14" ya da "%14,5" */
function formatPct(bp) {
  const v = Math.round(Number(bp) || 0);
  const neg = v < 0; const abs = Math.abs(v);
  const whole = Math.floor(abs / 100), frac = Math.round((abs % 100) / 10);
  const f = frac === 10 ? [whole + 1, 0] : [whole, frac];
  return `${neg ? "-" : ""}%${f[0]}${f[1] ? "," + f[1] : ""}`;
}
/** pay/payda → baz puan (tamsayı, yuvarlanmış); payda 0 → null */
function ratioBp(num, den) { return !den ? null : Math.round((num * 10000) / den); }

function parseYmd(s) { const [y, m, d] = String(s).slice(0, 10).split("-").map(Number); return { y, m, d }; }
function formatDate(ymd) { const { y, m, d } = parseYmd(ymd); return `${d} ${MONTHS[m - 1]} ${y}`; }
function formatDateShort(ymd) { const { m, d } = parseYmd(ymd); return `${d} ${MONTHS[m - 1]}`; }
function monthName(ymd) { return MONTHS_LONG[parseYmd(ymd).m - 1]; }
function weekdayName(ymd) { const { y, m, d } = parseYmd(ymd); return WEEKDAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()]; }
/** "SS:DD" (İstanbul ya da verilen dilim) */
function formatTime(d, tz = "Europe/Istanbul") {
  return new Intl.DateTimeFormat("en-GB", { timeZone: tz, hourCycle: "h23", hour: "2-digit", minute: "2-digit" }).format(new Date(d));
}
function daysBetween(fromYmd, toYmd) {
  const a = parseYmd(fromYmd), b = parseYmd(toYmd);
  return Math.round((Date.UTC(b.y, b.m - 1, b.d) - Date.UTC(a.y, a.m - 1, a.d)) / 86400000);
}
/** "Bugün" / "Yarın" / "Dün" / "3 gün önce" / "5 gün sonra" */
function relativeDay(ymd, todayYmd) {
  const n = daysBetween(todayYmd, ymd);
  if (n === 0) return "Bugün";
  if (n === 1) return "Yarın";
  if (n === -1) return "Dün";
  return n < 0 ? `${-n} gün önce` : `${n} gün sonra`;
}

// --- ünlü uyumu ---------------------------------------------------------------------------------
const VOWELS = "aeıioöuü";
const BACK = "aıou";
const isVowel = (c) => VOWELS.includes(c);
function lastVowel(w) { const s = lower(w); for (let i = s.length - 1; i >= 0; i--) if (isVowel(s[i])) return s[i]; return "e"; }
function vowelCount(w) { return [...lower(w)].filter(isVowel).length; }
const VOICELESS = "fstkçşhp"; // sert ünsüzler: "fıstıkçı şahap"
/** İkili uyum: a/e */
const two = (w) => (BACK.includes(lastVowel(w)) ? "a" : "e");
/** Dörtlü uyum: ı/i/u/ü */
function four(w) {
  const v = lastVowel(w);
  if ("aı".includes(v)) return "ı";
  if ("ei".includes(v)) return "i";
  if ("ou".includes(v)) return "u";
  return "ü";
}
/**
 * Hâl/iyelik eki. kind: dat(-e) · loc(-de) · abl(-den) · gen(-in) · acc(-i) · poss(-i; 3. tekil iyelik) · pl(-ler)
 * opts.proper: özel ad → kesme işareti eklenir ("Ahmet'e"), ünsüz yumuşaması (k→ğ) UYGULANMAZ.
 * Bilinen sınır: yalnız k→ğ yumuşaması (çok heceli sözcük) uygulanır; "kitap→kitabı" gibi p/ç/t yumuşamaları yoktur.
 */
function ek(word, kind, opts = {}) {
  let w = String(word == null ? "" : word).trim();
  if (!w) return w;
  const proper = !!opts.proper;
  const lw = lower(w);
  const lastCh = lw[lw.length - 1];
  const endsV = isVowel(lastCh);
  const apos = proper ? "'" : "";
  const soften = (suf) => (!proper && lastCh === "k" && vowelCount(lw) > 1 && /^[aeıioöuü]/.test(suf) ? w.slice(0, -1) + "ğ" : w);
  let base = w, suf;
  switch (kind) {
    case "dat": suf = (endsV ? "y" : "") + two(w); base = soften(suf); break;
    case "acc": suf = (endsV ? "y" : "") + four(w); base = soften(suf); break;
    case "poss": suf = (endsV ? "s" : "") + four(w); base = soften(suf); break;
    case "gen": suf = (endsV ? "n" : "") + four(w) + "n"; base = soften(suf); break;
    case "loc": suf = (VOICELESS.includes(lastCh) ? "t" : "d") + two(w); break;
    case "abl": suf = (VOICELESS.includes(lastCh) ? "t" : "d") + two(w) + "n"; break;
    case "pl": suf = "l" + two(w) + "r"; break;
    default: return w;
  }
  return base + apos + suf;
}
const plural = (w) => ek(w, "pl");
const firstName = (full) => String(full || "").trim().split(/\s+/)[0] || "";
/** "A, B ve C" */
function joinList(items) {
  const a = items.filter(Boolean);
  if (a.length <= 1) return a.join("");
  return a.slice(0, -1).join(", ") + " ve " + a[a.length - 1];
}
/** Sayı + tekil isim (Türkçe kuralı): countPhrase(3,"randevu") → "3 randevu" */
const countPhrase = (n, noun) => `${n} ${lower(noun)}`;

module.exports = {
  lower, upper, cap, formatTL, formatPct, ratioBp, formatDate, formatDateShort, monthName, weekdayName, formatTime, daysBetween, relativeDay,
  ek, plural, firstName, joinList, countPhrase, lastVowel, MONTHS, MONTHS_LONG, WEEKDAYS,
};
