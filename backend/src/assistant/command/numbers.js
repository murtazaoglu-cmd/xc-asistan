/**
 * Türkçe sayı ve tutar ayrıştırma (kural tabanlı). Girdi jetonları text.js:tokenize çıktısıdır ({t: katlanmış metin}).
 * Para hesabı KURUŞ (tamsayı) üzerinden yapılır; kayan nokta toplama kullanılmaz.
 */

const UNITS = { sifir: 0, bir: 1, iki: 2, uc: 3, dort: 4, bes: 5, alti: 6, yedi: 7, sekiz: 8, dokuz: 9 };
const TENS = { on: 10, yirmi: 20, otuz: 30, kirk: 40, elli: 50, altmis: 60, yetmis: 70, seksen: 80, doksan: 90 };
const NUM_WORDS = new Set([...Object.keys(UNITS), ...Object.keys(TENS), "yuz", "bin", "milyon", "milyar", "bucuk", "yarim"]);
const WORD_LIST = [...NUM_WORDS].filter((w) => w !== "bucuk" && w !== "yarim").sort((a, b) => b.length - a.length);

/** "yuzelli", "onbes", "ikibin" gibi bitişik yazımı sayı sözcüklerine böler; bölünemezse null */
function splitCompound(tok) {
  if (NUM_WORDS.has(tok)) return [tok];
  if (tok.length < 4 || tok.length > 30) return null;
  const memo = new Map();
  const go = (i) => {
    if (i === tok.length) return [];
    if (memo.has(i)) return memo.get(i);
    let res = null;
    for (const w of WORD_LIST) {
      if (tok.startsWith(w, i)) {
        const rest = go(i + w.length);
        if (rest) { res = [w, ...rest]; break; }
      }
    }
    memo.set(i, res);
    return res;
  };
  const r = go(0);
  return r && r.length >= 2 ? r : null;
}

/** Sayı sözcüğü dizisini değere çevirir: ["on","iki","bin","bes","yuz"] → 12500 */
function wordsToNumber(words) {
  let total = 0, cur = 0, seen = false;
  for (const w of words) {
    if (w in UNITS) { cur += UNITS[w]; seen = true; }
    else if (w in TENS) { cur += TENS[w]; seen = true; }
    else if (w === "yuz") { cur = (cur === 0 ? 1 : cur) * 100; seen = true; }
    else if (w === "bin") { total += (cur === 0 ? 1 : cur) * 1000; cur = 0; seen = true; }
    else if (w === "milyon") { total += (cur === 0 ? 1 : cur) * 1e6; cur = 0; seen = true; }
    else if (w === "milyar") { total += (cur === 0 ? 1 : cur) * 1e9; cur = 0; seen = true; }
    else if (w === "bucuk") { if (cur > 0) cur += 0.5; else total += 500; seen = true; }
    else if (w === "yarim") { cur += 0.5; seen = true; }
  }
  return seen ? total + cur : null;
}

/**
 * i. jetondan başlayarak ardışık sayı sözcüklerini okur. Dönüş: {value, next} veya null.
 * Not: "bin" tek başına 1000'dir ("bin lira"); "yarim" yalnız "yarım milyon/bin" gibi çarpanla anlamlıdır.
 */
function readWordNumber(tokens, i) {
  const words = [];
  let j = i;
  while (j < tokens.length) {
    const parts = splitCompound(tokens[j].t);
    if (!parts) break;
    words.push(...parts);
    j++;
  }
  if (!words.length) return null;
  if (words.length === 1 && (words[0] === "bucuk" || words[0] === "yarim")) return null;
  const value = wordsToNumber(words);
  if (value === null) return null;
  return { value, next: j };
}

/** "12.500" → 12500 ; "12,5" → 12.5 ; "1.250,50" → 1250.5 ; "12.5" → 12.5 ; geçersizse null */
function parseNumericString(s) {
  if (!/^\d[\d.,]*$/.test(s) || /[.,]$/.test(s)) return null;
  const hasDot = s.includes("."), hasComma = s.includes(",");
  let norm;
  if (hasDot && hasComma) {
    const lastDot = s.lastIndexOf("."), lastComma = s.lastIndexOf(",");
    const dec = lastDot > lastComma ? "." : ",";
    const thou = dec === "." ? "," : ".";
    const parts = s.split(dec);
    if (parts.length !== 2) return null;
    norm = parts[0].split(thou).join("") + "." + parts[1];
    if (!/^\d+\.\d+$/.test(norm)) return null;
  } else if (hasDot) {
    if (/^\d{1,3}(\.\d{3})+$/.test(s)) norm = s.split(".").join("");
    else if (/^\d+\.\d+$/.test(s)) norm = s;
    else return null;
  } else if (hasComma) {
    if (/^\d+,\d{1,2}$/.test(s)) norm = s.replace(",", ".");
    else if (/^\d{1,3}(,\d{3})+$/.test(s)) norm = s.split(",").join("");
    else return null;
  } else norm = s;
  const n = Number(norm);
  return Number.isFinite(n) ? n : null;
}

const CURRENCY = new Set(["tl", "try", "lira", "liralik", "₺", "turk"]);
const MULT = { bin: 1000, k: 1000, milyon: 1e6, milyar: 1e9 };

/** kuruş (tamsayı) → "12.500,50 TL" (Türkçe biçim; ,00 yoksa gösterilmez) */
function formatKurus(kurus) {
  const neg = kurus < 0; const k = Math.abs(Math.round(kurus));
  const lira = Math.floor(k / 100), kr = k % 100;
  const s = String(lira).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return (neg ? "-" : "") + s + (kr ? "," + String(kr).padStart(2, "0") : "") + " TL";
}

/** TL (ondalıklı sayı) → kuruş tamsayısı */
function toKurus(tl) { return Math.round(Number(tl) * 100); }

/**
 * Jetonlardan tutar çıkarır. used: başka ayrıştırıcıların (tarih/saat) tükettiği indeksler — atlanır.
 * Tutar sayılır: (a) para birimi işaretli sayı ("12.500 TL", "₺850"), (b) çarpanlı ("12 bin", "1,5 milyon"),
 * (c) sayı sözcükleri ("bin beş yüz"), (d) opts.allowBare ise ≥3 haneli çıplak sayı ("5000").
 * Dönüş: {value (TL), kurus, idx:[başla, bitir), currency:boolean, explicit} veya null. İlk uygun olan alınır.
 */
function extractAmount(tokens, used, opts = {}) {
  for (let i = 0; i < tokens.length; i++) {
    if (used.has(i)) continue;
    const t = tokens[i].t;
    // ₺ öneki
    if (t === "₺" && tokens[i + 1] && !used.has(i + 1)) {
      const v = parseNumericString(tokens[i + 1].t);
      if (v !== null) return mk(v, i, i + 2, true);
    }
    // rakamla başlayan
    if (/^\d[\d.,]*$/.test(t)) {
      if (t.replace(/\D/g, "").length >= 10 && !/[.,]/.test(t)) continue; // telefon / uzun kimlik
      if (/^\d{1,2}[:]\d{2}$/.test(t)) continue;
      const v = parseNumericString(t);
      if (v === null) continue;
      let j = i + 1, value = v, currency = false, mult = false;
      const nx = tokens[j] && !used.has(j) ? tokens[j].t : null;
      if (nx && MULT[nx]) {
        value = v * MULT[nx]; j++; mult = true;
        // "3 bin 500" → 3500
        const n2 = tokens[j] && !used.has(j) ? tokens[j].t : null;
        if (n2 && /^\d{1,3}$/.test(n2) && MULT[nx] >= 1000 && Number(n2) < MULT[nx] && !(tokens[j + 1] && /^(gun|hafta|ay|saat|dakika)$/.test(tokens[j + 1].t))) {
          value += Number(n2); j++;
        } else {
          // "12 bin beş yüz" (sayı sözcüğü kuyruğu)
          const wn = readWordNumber(tokens, j);
          if (wn && wn.value < MULT[nx] && !used.has(j)) { value += wn.value; j = wn.next; }
        }
      } else if (nx && /^(\d{1,3})$/.test(nx) === false) {
        // "5 yuz"? bırak
      }
      const c = tokens[j] && !used.has(j) ? tokens[j].t : null;
      if (c && CURRENCY.has(c)) { currency = true; j++; if (tokens[j] && tokens[j].t === "lik") j++; }
      if (mult || currency || (opts.allowBare && /^(\d{3,}|\d{1,3}(\.\d{3})+(,\d{1,2})?)$/.test(t))) return mk(value, i, j, currency);
      continue;
    }
    // sayı sözcükleri
    const wn = readWordNumber(tokens, i);
    if (wn) {
      let j = wn.next, value = wn.value;
      const c = tokens[j] && !used.has(j) ? tokens[j].t : null;
      let currency = false;
      if (c && CURRENCY.has(c)) { currency = true; j++; }
      // Birden fazla belirsiz kullanım ("iki gün") için: yalnız para işareti, çarpan ya da ≥100 değer kabul edilir
      const hasMult = tokens.slice(i, wn.next).some((x) => /^(bin|milyon|milyar)$/.test(splitCompound(x.t)?.slice(-1)[0] || "") || /(bin|milyon|yuz)/.test(x.t));
      if (currency || hasMult || value >= 100) {
        if (tokens[j] && /^(gun|hafta|ay|saat|dakika|kisi|adet|metre|m|cm)$/.test(tokens[j].t)) continue;
        return mk(value, i, j, currency);
      }
      i = wn.next - 1;
    }
  }
  return null;
  function mk(value, a, b, currency) {
    const kurus = toKurus(value);
    return { value: kurus / 100, kurus, idx: [a, b], currency, explicit: true };
  }
}

module.exports = { splitCompound, wordsToNumber, readWordNumber, parseNumericString, extractAmount, formatKurus, toKurus, UNITS, TENS, NUM_WORDS };
