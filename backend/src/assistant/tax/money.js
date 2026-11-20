/**
 * Para yardımcıları — TÜM hesaplar kuruş TAMSAYISI ile yapılır (float yok).
 * Mevcut payments/expenses/projects NUMERIC(…,2) TL kalır; sınırda toKurus/fromKurus ile çevrilir.
 */

/** Güvenli üst sınır: 10 milyar TL (1e12 kuruş). BigInt ara hesabı taşma riskini ayrıca kapatır. */
const MAX_KURUS = 1e12;

/** Sayı mı (sonlu, NaN/Infinity değil)? */
const isNum = (v) => typeof v === "number" && Number.isFinite(v);

/**
 * TL (sayı ya da "1250.50" metni; virgül KABUL EDİLMEZ — API sözleşmesi) → kuruş tamsayısı. Geçersizse null.
 * 1250.5 → 125050; "0.1" + "0.2" gibi float tuzakları için metinden/yuvarlayarak çevrilir.
 */
function toKurus(tl) {
  let n;
  if (typeof tl === "string") {
    if (!/^-?\d{1,13}(\.\d{1,2})?$/.test(tl.trim())) return null;
    n = Number(tl.trim());
  } else n = tl;
  if (!isNum(n)) return null;
  const k = Math.round(n * 100 + (n < 0 ? -1e-9 : 1e-9)); // 1.005*100 = 100.49999… tuzağına karşı küçük epsilon
  return Math.abs(k) > MAX_KURUS ? null : k;
}

/** kuruş → TL (sayı, 2 ondalık). payments/expenses NUMERIC sütunlarına yazarken kullanılır. */
function fromKurus(k) {
  return Math.round(k) / 100;
}

/** Tamsayı bölme, yarım yukarı (half-up; negatifte sıfırdan uzağa). BigInt ile taşmasız. a, b tamsayı; b > 0 */
function divRound(a, b) {
  const A = BigInt(a), B = BigInt(b);
  const neg = A < 0n;
  const q = ((neg ? -A : A) * 2n + B) / (2n * B);
  return Number(neg ? -q : q);
}

/** Çarpma + bölme tek adımda: round(a * m / d) (ara değer BigInt) */
function mulDiv(a, m, d) {
  const A = BigInt(a) * BigInt(m);
  const D = BigInt(d);
  const neg = A < 0n;
  const q = ((neg ? -A : A) * 2n + D) / (2n * D);
  return Number(neg ? -q : q);
}

/** Geçerli, negatif olmayan kuruş tamsayısı mı (üst sınır dahil) */
const isKurus = (v) => Number.isInteger(v) && v >= 0 && v <= MAX_KURUS;

module.exports = { MAX_KURUS, toKurus, fromKurus, divRound, mulDiv, isKurus, isNum };
