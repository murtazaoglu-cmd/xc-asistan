/**
 * Müşteri adı eşleme: bulanık, Türkçe karakter ve ek (çekim eki) toleranslı.
 *   "Ahmet Bey'in", "ahmetin", "Ayşe Hanım'a", "ayseye", "Mehmed'e" → aday listesindeki kayda eşlenir.
 * Aday: {key, name, phone?}. Sonuç: {matched, candidates[], query, span:Set(indeks)}.
 * Belirsizse (birden çok aday yakın skorda) candidates doludur ve matched null kalır — arayüz seçenek listesi gösterir.
 */
const { fold, lev } = require("./text");
const { WEEKDAYS, MONTHS } = require("./datetime");

const HONORIFIC_RE = /^(bey|hanim|hn|abi|abla|usta|ustam|hoca|hocam|bayan|sayin|dr|doktor|muhendis|mimar|komsu|bay|kardes|amca|teyze|yenge|efendi)(in|i|e|a|den|dan|le|la|ye|ya|ne|na|nin|nun|un|u|dir)?$/;
const NAME_SUFFIXES = ["a", "e", "i", "u", "in", "un", "nin", "nun", "ye", "ya", "yi", "yu", "ne", "na", "ni", "nu", "den", "dan", "ten", "tan", "de", "da", "te", "ta", "le", "la", "yle", "yla", "ile", "ine", "ina", "nde", "nda", "si", "su", "im", "imiz", "ler", "lar", "leri", "lari", "lerin", "larin", "gil", "gile", "gilin", "gilden"];
const SUFFIX_SET = new Set(NAME_SUFFIXES);

// Ad olarak eşleşmemesi gereken (komut anahtar) sözcükler; tek başına eşleşme engellenir
const RESERVED = new Set([
  ...Object.keys(WEEKDAYS), ...Object.keys(MONTHS),
  "bugun", "yarin", "dun", "randevu", "kesif", "montaj", "odeme", "tahsilat", "gider", "masraf", "not", "hatirlat", "teklif", "musteri",
  "ekle", "ara", "bul", "sil", "iptal", "ertele", "bana", "bin", "tl", "lira", "saat", "gun", "hafta", "ay", "sabah", "aksam", "gece", "oglen",
  "kabul", "red", "ne", "var", "kim", "kimden", "alacak", "alacagim", "borc", "toplam", "kadar", "icin", "ile", "ve", "bir", "iki", "uc", "dort",
  "bes", "alti", "yedi", "sekiz", "dokuz", "on", "yuz", "havale", "nakit", "kart", "kredi", "projesi", "proje", "durum", "durumu", "yap", "et", "gelecek", "gecen",
  "kur", "sor", "haftaya", "bu", "sonra", "once", "gibi", "da", "de", "ta", "te", "mi", "mu", "diye", "ben", "sen", "biz", "yeni", "tum", "tüm", "bütün", "hepsi",
]);

function stripHonorifics(toks) { return toks.filter((t) => !HONORIFIC_RE.test(t)); }

/** Aday listesini eşleştirme için hazırlar (katlanmış, unvansız ad jetonları) */
function prepareCandidates(list) {
  return list.map((c) => {
    const toks = fold(c.name || "").replace(/['’]/g, " ").split(/\s+/).filter(Boolean);
    const core = stripHonorifics(toks);
    return { ...c, _toks: core.length ? core : toks };
  });
}

function sameStem(a, b) {
  if (a === b) return true;
  // Ahmed'e ↔ Ahmet: sondaki d/t yumuşaması
  if (a.length === b.length && a.length >= 4 && a.slice(0, -1) === b.slice(0, -1) && /[dt]$/.test(a) && /[dt]$/.test(b)) return true;
  return false;
}

/** metin jetonu (tt) ad jetonuna (nt) ne kadar uyar: 0..1 */
function tokenScore(tt, nt) {
  if (!tt || !nt) return 0;
  if (sameStem(tt, nt)) return 1;
  if (tt.startsWith(nt) || (nt.length >= 4 && tt.length >= nt.length && tt.startsWith(nt.slice(0, -1)) && /[dt]$/.test(nt))) {
    const rest = tt.startsWith(nt) ? tt.slice(nt.length) : tt.slice(nt.length - 1);
    if (rest.length === 0 ? tt === nt : (SUFFIX_SET.has(rest) || (rest.length <= 6 && isSuffixChain(rest)))) return 0.95;
  }
  if (nt.length >= 5 && tt.length >= 4) {
    const maxD = nt.length >= 8 ? 2 : 1;
    const d = lev(tt, nt, maxD);
    if (d <= maxD) return d === 1 ? 0.82 : 0.72;
    // ekli + yazım hatası
    for (const sfx of ["a", "e", "in", "un", "ye", "ya", "dan", "den", "i", "u"]) {
      if (tt.endsWith(sfx) && tt.length - sfx.length >= 4) { const d2 = lev(tt.slice(0, -sfx.length), nt, 1); if (d2 <= 1) return 0.78; }
    }
  }
  return 0;
}
function isSuffixChain(r) {
  if (!r) return true;
  if (SUFFIX_SET.has(r)) return true;
  for (let i = 1; i < r.length; i++) if (SUFFIX_SET.has(r.slice(0, i)) && isSuffixChain(r.slice(i))) return true;
  return false;
}

const isDateKeyword = (t) => t in WEEKDAYS || t in MONTHS || t === "bugun" || t === "yarin";

/**
 * tokens: tokenize() jetonları; used: dışlanacak indeksler (kullanılan jetonlar); cands: prepareCandidates çıktısı.
 * opts.phase: "full" → yalnız ≥2 jetonlu tam ad eşleşmeleri (tarih sözcüğü ad olabilsin diye); "any" → tek jeton eşleşmesi de.
 */
function matchCustomers(tokens, used, cands, opts = {}) {
  const phase = opts.phase || "any";
  const hits = [];
  for (const c of cands) {
    const nts = c._toks;
    if (!nts.length) continue;
    let matchedIdx = [], quality = [];
    let positions = [];
    for (const nt of nts) {
      let best = { s: 0, i: -1 };
      for (let i = 0; i < tokens.length; i++) {
        if (used.has(i) || positions.includes(i)) continue;
        const tt = tokens[i].t;
        if (RESERVED.has(tt) && tt !== nt) continue;
        if (tt.length < 2 || /^\d/.test(tt)) continue;
        if (HONORIFIC_RE.test(tt) && !nts.includes(tt)) continue;
        if (SUFFIX_SET.has(tt) && tt.length <= 2 && tt !== nt) continue;
        const s = tokenScore(tt, nt);
        if (s > best.s) best = { s, i };
      }
      if (best.s >= 0.7) { positions.push(best.i); quality.push(best.s); matchedIdx.push(nts.indexOf(nt)); }
    }
    if (!positions.length) continue;
    const full = positions.length === nts.length;
    if (phase === "full" && !(full && nts.length >= 2)) continue;
    // tek tokenlı eşleşmede tarih sözcüğü adı olamaz (örn. "cuma", "kasım"), ancak aday adı zaten o ise ve honorific eşlik ediyorsa kabul
    if (positions.length === 1) {
      const tk = tokens[positions[0]];
      if (isDateKeyword(tk.t)) {
        const nxt = tokens[positions[0] + 1];
        if (!(nxt && HONORIFIC_RE.test(nxt.t))) continue;
      }
    }
    const avg = quality.reduce((a, b) => a + b, 0) / quality.length;
    let score;
    if (full) score = avg;
    else if (matchedIdx.includes(0)) score = 0.7 * avg + 0.0; // ilk ad eşleşti
    else score = 0.62 * avg; // yalnız soyad
    // sıra bonusu (ad soyad bitişik ve doğru sıra)
    if (full && nts.length >= 2) { const sorted = [...positions].sort((a, b) => a - b); if (sorted.every((p, k) => k === 0 || p === sorted[k - 1] + 1)) score = Math.min(1, score + 0.03); }
    if (score < 0.6) continue;
    hits.push({ cand: c, score: Math.round(score * 1000) / 1000, positions, full });
  }
  return hits;
}

/**
 * Eşleşmeleri karara bağlar.
 *  → {matched, candidates, positions}
 *  Tek aday → matched. Birden çok aday ve en yüksek skor net (≥0.12 fark) → matched. Aksi → candidates (belirsiz).
 */
function decide(hits) {
  if (!hits.length) return { matched: null, candidates: [], positions: [] };
  hits.sort((a, b) => b.score - a.score || String(a.cand.name).localeCompare(String(b.cand.name), "tr"));
  const top = hits[0];
  const close = hits.filter((h) => top.score - h.score < 0.12);
  const strip = (h) => ({ key: h.cand.key, name: h.cand.name, phone: h.cand.phone || null, score: h.score });
  if (close.length === 1) {
    return { matched: strip(top), candidates: [], positions: top.positions };
  }
  return { matched: null, candidates: close.slice(0, 6).map(strip), positions: [...new Set(close.flatMap((h) => h.positions))] };
}

/** Aday bulunamadığında yazılan adı sezgisel bulur: unvanın önündeki 1–2 sözcük ya da büyük harfli ardışık sözcükler */
function guessQuery(tokens, used) {
  for (let i = 0; i < tokens.length; i++) {
    if (used.has(i)) continue;
    if (HONORIFIC_RE.test(tokens[i].t) && i > 0) {
      const names = [];
      for (let k = i - 1; k >= 0 && names.length < 2; k--) {
        const tk = tokens[k];
        if (used.has(k) || RESERVED.has(tk.t) || !/^[a-zçğıöşü]+$/i.test(tk.o) || /^\d/.test(tk.t) || SUFFIX_SET.has(tk.t)) break;
        names.unshift(k);
      }
      if (names.length) return { query: [...names.map((k) => tokens[k].o), tokens[i].o.replace(/(in|i|e|a|den|dan|le|la|ye|ya|ne|na|nin|nun|un|u)$/i, (m, g, off, s) => (/^(bey|hanım|hanim|hn|abi|abla|usta|hoca|bayan)/i.test(s.slice(0, off)) ? "" : m))].join(" "), idx: [...names, i] };
    }
  }
  // büyük harfli sözcük öbeği (cümle başı değilse)
  let best = null;
  for (let i = 1; i < tokens.length; i++) {
    if (used.has(i) || !tokens[i].cap || RESERVED.has(tokens[i].t) || /^(OFR|PRJ)-/i.test(tokens[i].o)) continue;
    if (SUFFIX_SET.has(tokens[i].t)) continue;
    const run = [i];
    while (tokens[run[run.length - 1] + 1] && tokens[run[run.length - 1] + 1].cap && !used.has(run[run.length - 1] + 1) && !RESERVED.has(tokens[run[run.length - 1] + 1].t)) run.push(run[run.length - 1] + 1);
    if (!best || run.length > best.idx.length) best = { query: run.map((k) => tokens[k].o).join(" "), idx: run };
  }
  return best;
}

module.exports = { prepareCandidates, matchCustomers, decide, guessQuery, HONORIFIC_RE, RESERVED, tokenScore, SUFFIX_SET };
