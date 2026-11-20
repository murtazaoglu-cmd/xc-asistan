/**
 * Türkçe metin yardımcıları (saf fonksiyonlar): büyük/küçük harf (İ/ı), özel ad hâl ekleri (ünlü uyumu,
 * kaynaştırma, sert ünsüz benzeşmesi), TL/tarih biçimleri. WhatsApp şablonlarında kullanılır.
 */
const lowerTr = (s) => String(s).toLocaleLowerCase("tr-TR");
const upperTr = (s) => String(s).toLocaleUpperCase("tr-TR");

/** "ahmet YILMAZ" → "Ahmet Yılmaz"; kesme işaretinden sonrası küçük kalır ("ali'nin" → "Ali'nin") */
function titleCaseTr(s) {
  return String(s).trim().replace(/\s+/g, " ").split(" ").map((w) =>
    w.split("-").map((p) => { const l = lowerTr(p); return l ? upperTr(l.charAt(0)) + l.slice(1) : l; }).join("-")).join(" ");
}
const firstName = (full) => titleCaseTr(String(full || "").trim().split(/\s+/)[0] || "");

const VOWELS = "aeıioöuü";
const FRONT = "eiöü", ROUNDED = "oöuü";
const VOICELESS = "çfhkpsşt";

// Ünlü uyumuna uymayan (ince "l" ile biten, art ünlülü) yaygın özel adlar: Kemal'e, Cemal'e, Nihal'e
const SOFT_L_EXCEPTIONS = new Set(["kemal", "cemal", "nihal", "kamal"]);

function lastVowel(w) {
  const l = lowerTr(w);
  if (SOFT_L_EXCEPTIONS.has(l)) return "e";
  for (let i = l.length - 1; i >= 0; i--) if (VOWELS.includes(l[i])) return l[i];
  return "e";
}
const endsWithVowel = (w) => VOWELS.includes(lowerTr(w).slice(-1));
const lastLetter = (w) => lowerTr(w).replace(/[^a-zçğıöşü0-9]/g, "").slice(-1);

/**
 * Özel ada hâl eki ekler. kind: 'e' (yönelme), 'i' (belirtme), 'de' (bulunma), 'den' (ayrılma), 'in' (ilgi), 'ile' (vasıta).
 * Özel adlarda kesme işareti konur ve ünsüz yumuşaması yapılmaz (Burak'a, Ahmet'e, Ayşe'ye, Ali'nin).
 */
function suffix(word, kind, { apostrophe = true } = {}) {
  const w = String(word || "").trim();
  if (!w) return "";
  const v = lastVowel(w);
  const front = FRONT.includes(v), rounded = ROUNDED.includes(v);
  const vowelEnd = endsWithVowel(w);
  const two = front ? "e" : "a";
  const four = front ? (rounded ? "ü" : "i") : rounded ? "u" : "ı";
  const hard = VOICELESS.includes(lastLetter(w));
  let s;
  switch (kind) {
    case "e": s = (vowelEnd ? "y" : "") + two; break;
    case "i": s = (vowelEnd ? "y" : "") + four; break;
    case "in": s = (vowelEnd ? "n" : "") + four + "n"; break;
    case "de": s = (hard ? "t" : "d") + two; break;
    case "den": s = (hard ? "t" : "d") + two + "n"; break;
    case "ile": s = (vowelEnd ? "yl" : "l") + two; break;
    default: return w;
  }
  return w + (apostrophe ? "'" : "") + s;
}

/** Kuruş → "1.250,50"; trimZero=true iken ",00" atılır ("1.250"). Negatif desteklenir. */
function formatTL(kurus, { trimZero = true } = {}) {
  const neg = kurus < 0; const abs = Math.abs(Math.round(kurus));
  const lira = String(Math.floor(abs / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  const kr = String(abs % 100).padStart(2, "0");
  const body = trimZero && kr === "00" ? lira : `${lira},${kr}`;
  return (neg ? "-" : "") + body;
}

const MONTHS = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];
const DAYS = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"];
/** "2026-12-05" → "5 Aralık 2026" */
function formatDateTr(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""));
  return m ? `${+m[3]} ${MONTHS[+m[2] - 1]} ${m[1]}` : "";
}
/** "2026-12-05" → "05.12.2026" */
function formatDateShort(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""));
  return m ? `${m[3]}.${m[2]}.${m[1]}` : "";
}
/** "2026-12-05" → "Cumartesi" */
function weekdayTr(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""));
  return m ? DAYS[new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])).getUTCDay()] : "";
}

module.exports = { lowerTr, upperTr, titleCaseTr, firstName, suffix, formatTL, formatDateTr, formatDateShort, weekdayTr, MONTHS, DAYS };
