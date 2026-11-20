const { clean, fold } = require("./text");

const APOS = /['’‘`´ʼ]/;
const EDGE_PUNCT = /^[?!"()\[\]{}.,;:*_~<>|\\\/-]+|[?!"()\[\]{}.,;:*_~<>|\\\/-]+$/g;

/**
 * Komut metnini jetonlara böler.
 *  - kesme işaretinden ayırır ("Bey'in" → "Bey","in"; "10'da" → "10","da")
 *  - rakam-harf sınırından ayırır ("12bin" → "12","bin"; "850₺" → "850","₺")
 *  - uç noktalama temizlenir ama `punct` alanında saklanır (not: "Ahmet Bey: ..." iki nokta bilgisi için)
 * Jeton: {t: katlanmış, o: özgün parça, wi: özgün sözcük sırası, punct: sonda sökülen noktalama, cap: büyük harfle mi başlıyor}
 */
function tokenize(text) {
  const words = clean(text).trim().split(/\s+/).filter(Boolean);
  const tokens = [];
  words.forEach((w, wi) => {
    const pieces = w.split(APOS).filter((p) => p !== "");
    pieces.forEach((p, pi) => {
      let lead = "", trail = "";
      const m = /^([?!"()\[\]{}.,;:*_~<>|\\\/-]*)(.*?)([?!"()\[\]{}.,;:*_~<>|\\\/-]*)$/.exec(p);
      if (m) { lead = m[1]; p = m[2]; trail = m[3]; }
      if (!p) return;
      // "kod" benzeri (OFR-1003, PRJ-501, e-posta, adres) olduğu gibi kalsın
      if (/^[A-Za-zÇĞİÖŞÜçğıöşü]{2,5}-\d{1,8}$/.test(p)) { tokens.push(mk(p, wi, trail, pi)); return; }
      // rakam↔harf ayır: 12bin, 5000tl, ₺850
      const parts = p.replace(/(\d)([A-Za-zÇĞİÖŞÜçğıöşü₺])/g, "$1 $2").replace(/([₺])(\d)/g, "$1 $2").replace(/([A-Za-zÇĞİÖŞÜçğıöşü])(\d)/g, "$1 $2").split(" ").filter(Boolean);
      parts.forEach((q, qi) => tokens.push(mk(q, wi, qi === parts.length - 1 ? trail : "", pi)));
    });
  });
  return tokens;

  function mk(o, wi, punct, pi) {
    return { t: fold(o), o, wi, punct: punct || "", cap: /^[A-ZÇĞİÖŞÜ]/.test(o) };
  }
}

/** Kullanılmayan jetonların özgün sözcüklerinden metin kurar (başlık/not için) */
function remainder(tokens, used, skip = () => false) {
  const words = [];
  const seen = new Set();
  // sözcüğün tüm parçaları kullanılmamışsa sözcüğü olduğu gibi al; kısmen kullanılmışsa kalan parçaları ekle
  const byWord = new Map();
  tokens.forEach((tk, i) => { if (!byWord.has(tk.wi)) byWord.set(tk.wi, []); byWord.get(tk.wi).push(i); });
  for (const [wi, idxs] of byWord) {
    const free = idxs.filter((i) => !used.has(i) && !skip(tokens[i], i));
    if (!free.length) continue;
    if (free.length === idxs.length) { words.push(restore(idxs.map((i) => tokens[i]))); }
    else words.push(free.map((i) => tokens[i].o).join(" "));
    seen.add(wi);
  }
  return words.join(" ").replace(/\s+/g, " ").trim();
  function restore(toks) {
    // parçaları kesme işaretiyle birleştirme bilgisi yok; ek parçaları kesmeyle bağla (Bey'in)
    return toks.map((t, k) => (k === 0 ? t.o : (/^[a-zçğıöşü]{1,4}$/i.test(t.o) && !/^\d/.test(toks[k - 1].o) ? "'" + t.o : " " + t.o))).join("");
  }
}

module.exports = { tokenize, remainder };
