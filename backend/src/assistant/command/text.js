/**
 * Türkçe metin yardımcıları (kural tabanlı ayrıştırıcının temeli). Kütüphane gerektirmez.
 * - lowerTr: Türkçe büyük/küçük harf kuralı (İ→i, I→ı)
 * - fold: aksan katlama (ç→c, ğ→g, ı→i, ö→o, ş→s, ü→u) — eşleştirmede kullanılır, kullanıcıya gösterilmez
 * - tokenize: kesme işareti / noktalama temizlenmiş, ek tolerans için ayrılmış jetonlar
 */

const FOLD_MAP = { "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "â": "a", "î": "i", "û": "u", "İ": "i", "I": "i" };

function lowerTr(s) {
  return String(s).replace(/İ/g, "i").replace(/I/g, "ı").toLowerCase();
}

function fold(s) {
  return lowerTr(s).replace(/[çğışöüâîû]/g, (c) => FOLD_MAP[c] || c);
}

// Görünmez/yön işaretleri ve alışılmadık boşluklar
const INVISIBLE_RE = /[​-‏‪-‮⁠-⁩﻿­]/g;
const SPACE_RE = /[    　]/g;

/** Kontrol/yön karakterlerini temizler, boşlukları tekleştirir (satır sonlarını korumaz) */
function clean(s) {
  return String(s).replace(INVISIBLE_RE, "").replace(SPACE_RE, " ").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, " ");
}

/**
 * Komut metnini eşleştirme biçimine getirir: katlanmış, kesme işaretleri boşluk, birden fazla boşluk tek.
 * Noktalama (. , : ;) sayı/saat ayrıştırması için KORUNUR; yalnız ? ! " ( ) kaldırılır.
 */
function normalize(s) {
  return fold(clean(s))
    .replace(/['’‘`´ʼ]/g, " ")
    .replace(/[?!"()\[\]{}]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Orijinal (büyük/küçük harfi korunmuş) metin için kesme işareti normalizasyonu */
function tidy(s) {
  return clean(s).replace(/\s+/g, " ").trim();
}

/** Levenshtein mesafesi (kısa dizeler için; üst sınır aşılırsa erken çıkar) */
function lev(a, b, max = 3) {
  if (a === b) return 0;
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

/** Baş harfleri büyük, Türkçe uyumlu ("ahmet yılmaz" → "Ahmet Yılmaz") */
function titleCase(s) {
  return String(s).split(/\s+/).filter(Boolean).map((w) => {
    const first = w.charAt(0);
    const up = first === "i" ? "İ" : first === "ı" ? "I" : first.toLocaleUpperCase("tr");
    return up + lowerTr(w.slice(1));
  }).join(" ");
}

module.exports = { lowerTr, fold, clean, normalize, tidy, lev, titleCase };
