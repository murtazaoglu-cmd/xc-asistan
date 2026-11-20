/**
 * Kural tabanlı (regex + anahtar kelime) yazışma çıkarıcı. LLM yoktur; metin dışarı gönderilmez.
 * Mesajlardan ÖNERİ üretir (not / hatırlatma / randevu); hiçbir şey kendiliğinden uygulanmaz — kullanıcı onaylar.
 * Her öneri kaynak mesaja (msgIndex) bağlıdır. Göreli tarihler MESAJIN gönderildiği ana göre çözülür;
 * çözülen tarih içe aktarma anından önceyse (geçmiş) randevu/hatırlatma önerilmez (not olarak kalabilir).
 */
const crypto = require("crypto");
const { tokenize } = require("../command/tokenize");
const { parseDateTime, todayOf, addDays } = require("../command/datetime");
const { extractAmount, formatKurus } = require("../command/numbers");
const { fold } = require("../command/text");

const MAX_NOTES = 120;
const MAX_TOTAL = 250;

const TAGS = [
  ["sikayet", /\b(sikayet\w*|memnun\s+degil|memnun\s+kalmadim|bozuk|calismiyor|calismadi|kotu|sorun\w*|problem\w*|gecikti|geciktin\w*|hasarli|kirik|kirildi|sizdir\w*|akit\w*|yanlis)\b/],
  ["garanti", /\bgaranti\w*\b/],
  ["kesif", /\b(kesif\w*|kesfe)\b/],
  ["odeme", /\b(odeme\w*|odedim|odedik|havale\w*|eft|dekont\w*|tahsilat\w*|iban|taksit\w*|nakit)\b/],
  ["fiyat", /\b(fiyat\w*|ucret\w*|kac\s+para|kac\s+tl|ne\s+kadar|butce\w*|pazarlik\w*|indirim\w*|teklif\w*)\b/],
  ["olcu", /\b(olcu\w*|olcum\w*|yukseklik\w*|genislik\w*|en\s+\d|boy\s+\d)\b/],
];
const CUE_APPT = /\b(gel(ir|irim|irsin|irsiniz|ebilir|ebilirsiniz|ebilirsin|ecegim|ecek|eceksiniz|in|sene|sin)?|gelir\s+misiniz|ugra\w*|ugrar\w*|evde\w*|evdeyim|evdeyiz|musait\w*|bekliyor\w*|bekler\w*|oluruz|olurum|olacagim|olacagiz|kesif\w*|olcu\w*|montaj\w*|randevu\w*|gorusel\w*|gorusur\w*|buluss\w*|isyerinde\w*|dukkanda\w*|ofiste\w*)\b/;
const CUE_PAY = /\b(odeme\w*|ode(yecegim|yecegiz|rim|riz|rsiniz|mesi|nir|necek|yelim)|havale\w*|eft|gonder(irim|ecegim|ecegiz|irim)|yatir(irim|acagim|acagiz|iriz)|tahsil\w*|maas\w*|borc\w*|kalan\w*|taksit\w*|para\w*)\b/;
const CUE_REMIND = /\b(hatirla\w*|unutma\w*|haber\s+ver\w*|geri\s+don\w*|arayin|arar\s+misiniz|arasin|donus\s+yap\w*|bildir\w*|dusun(up|elim|ecegim)\w*)\b/;
const PHONE_RE = /(?:\+?90[\s.-]?)?\(?0?5\d{2}\)?[\s.-]?\d{3}[\s.-]?\d{2}[\s.-]?\d{2}\b/;
const MEAS_RE = /\b\d+(?:[.,]\d+)?\s*(?:x|×|\*)\s*\d+(?:[.,]\d+)?(?:\s*(?:x|×|\*)\s*\d+(?:[.,]\d+)?)?\s*(?:cm|mm|m|metre|santim)?\b|\b(?:olcu\w*|olcum\w*|yukseklik\w*|genislik\w*|en|boy|derinlik\w*)\s*[:=]?\s*\d+(?:[.,]\d+)?\s*(?:cm|mm|m|metre|santim)?\b/i;
const ADDR_CUES = [/\b(mah(allesi)?|mh)\b\.?/i, /\b(sok(ak|agi)?|sk)\b\.?/i, /\b(cad(desi|de)?|cd)\b\.?/i, /\b(bulvar\w*|blv)\b\.?/i, /\bno\s*[:.]?\s*\d+/i, /\b(apt|apartman\w*)\b\.?/i, /\bdaire\s*[:.]?\s*\d+/i, /\bkat\s*[:.]?\s*\d+/i, /\b(site(si)?|blok)\b/i, /\bd\s*:\s*\d+/i];

const sha = (s) => crypto.createHash("sha1").update(s).digest("hex").slice(0, 20);
const clip = (s, n) => (s.length > n ? s.slice(0, n - 1).trimEnd() + "…" : s);
const squeeze = (s) => s.replace(/\s+/g, " ").trim();

const ABBR = /(^|[^A-Za-zÇĞİÖŞÜçğıöşü])(mah|mh|sok|sk|cad|cd|blv|bulv|apt|no|kat|d|dr|prof|sn|bkz|vb|vs|örn|ör|tel|st|ave|adr)\./gi;
function sentences(text) {
  const protectedText = String(text).replace(ABBR, "$1$2\u0001");
  return protectedText.split(/[\n!?]+|\.(?=\s|$)/).map((s) => squeeze(s.replace(/\u0001/g, "."))).filter((s) => s.length >= 3);
}

/**
 * @param {Array<{role:string, sender:string, content:string, sent_at:Date}>} msgs  (kronolojik)
 * @param {{now?:Date, customerName?:string}} opts
 * @returns {Array<{msgIndex:number, kind:'not'|'hatirlatma'|'randevu', payload:object, confidence:number, dedupeKey:string}>}
 */
function extractSuggestions(msgs, opts = {}) {
  const now = opts.now ? new Date(opts.now) : new Date();
  const today = todayOf(now);
  const who = opts.customerName ? String(opts.customerName).slice(0, 80) : "Müşteri";
  const out = [];
  const seen = new Set();
  const add = (msgIndex, kind, payload, confidence, sub) => {
    const key = sha(`${kind}|${msgIndex}|${sub}`);
    if (seen.has(key)) return;
    seen.add(key);
    out.push({ msgIndex, kind, payload, confidence, dedupeKey: key });
  };

  for (let mi = msgs.length - 1; mi >= 0; mi--) { // yeniden eskiye: not sınırı aşılırsa eskiler düşer
    const m = msgs[mi];
    if (!m.content) continue;
    const when = new Date(m.sent_at);
    let noteCountThisMsg = 0;
    for (const s of sentences(m.content)) {
      const f = fold(s);
      const tokens = tokenize(s);
      const used = new Set();
      const dt = parseDateTime(tokens, used, when, { assumeDateFromTime: false });
      const futureDate = dt.hasDate && dt.date >= today && !dt.relativePast;
      const amtTokens = tokens; const amt = extractAmount(amtTokens, new Set([...used]), { allowBare: /\b(tl|lira|fiyat|ucret|odeme|havale|bedel|toplam|butce)\b/.test(f) });

      // --- randevu / müsaitlik
      if (dt.hasDate && futureDate && CUE_APPT.test(f) && !CUE_PAY.test(f) && !CUE_REMIND.test(f)) {
        const type = /\bmontaj\w*\b/.test(f) ? "montaj" : "kesif";
        const addr = ADDR_CUES.filter((re) => re.test(s)).length >= 2 ? clip(s, 200) : null;
        add(mi, "randevu", {
          title: `${who} — ${type === "montaj" ? "Montaj" : "Keşif"}`, type, date: dt.date, time: dt.hasTime && !dt.approxTime ? dt.time : null,
          excerpt: clip(s, 240), ambiguities: dt.ambiguities.map((a) => a.kind), address: addr, by: m.role,
        }, dt.hasTime ? 0.8 : 0.65, `${dt.date}|${dt.time || ""}|${type}`);
        continue;
      }
      // --- ödeme sözü / hatırlatma (tarihli)
      if (dt.hasDate && futureDate && (CUE_PAY.test(f) || CUE_REMIND.test(f))) {
        const isPay = CUE_PAY.test(f);
        const title = isPay
          ? `${who}: ödeme sözü${amt ? " — " + formatKurus(amt.kurus) : ""}`
          : `${who}: ${clip(s, 80)}`;
        add(mi, "hatirlatma", {
          title: clip(title, 200), date: dt.date, time: dt.hasTime && !dt.approxTime ? dt.time : "09:00", amount: amt ? amt.value : null,
          excerpt: clip(s, 240), ambiguities: dt.ambiguities.map((a) => a.kind), by: m.role,
        }, isPay ? 0.7 : 0.6, `${dt.date}|${isPay ? "p" : "r"}`);
        continue;
      }
      // --- notlar (tarih gerekmez)
      if (noteCountThisMsg >= 3) continue;
      const tags = TAGS.filter(([, re]) => re.test(f)).map(([t]) => t);
      const meas = MEAS_RE.exec(s);
      if (meas) { add(mi, "not", { body: `Ölçü: ${squeeze(meas[0])} (“${clip(s, 160)}”)`, tags: uniq(["olcu", ...tags]), by: m.role }, 0.7, `olcu|${squeeze(meas[0])}`); noteCountThisMsg++; continue; }
      if (ADDR_CUES.filter((re) => re.test(s)).length >= 2) { add(mi, "not", { body: `Adres: ${clip(s, 240)}`, tags: uniq(["adres", ...tags]), by: m.role }, 0.7, "adres"); noteCountThisMsg++; continue; }
      const ph = PHONE_RE.exec(s);
      if (ph) { add(mi, "not", { body: `Telefon: ${squeeze(ph[0])}`, tags: uniq(["telefon", ...tags]), by: m.role }, 0.75, `tel|${ph[0].replace(/\D/g, "")}`); noteCountThisMsg++; continue; }
      if (amt && (tags.includes("fiyat") || tags.includes("odeme") || amt.currency)) {
        add(mi, "not", { body: `${tags.includes("odeme") && !tags.includes("fiyat") ? "Ödeme" : "Fiyat"}: ${formatKurus(amt.kurus)} (“${clip(s, 160)}”)`, tags: uniq([tags.includes("odeme") && !tags.includes("fiyat") ? "odeme" : "fiyat", ...tags]), by: m.role }, 0.65, `tutar|${amt.kurus}`);
        noteCountThisMsg++; continue;
      }
      if (tags.includes("sikayet") || tags.includes("garanti")) { add(mi, "not", { body: `${tags.includes("sikayet") ? "Şikâyet/sorun" : "Garanti"}: ${clip(s, 240)}`, tags: uniq(tags), by: m.role }, 0.6, `etiket|${tags.join(",")}|${clip(s, 40)}`); noteCountThisMsg++; continue; }
    }
  }
  // not sınırı (en yeniler kalsın): yukarıdaki döngü yeniden eskiye gittiği için baştakiler en yenidir
  let notes = 0;
  const limited = out.filter((x) => { if (x.kind !== "not") return true; notes++; return notes <= MAX_NOTES; });

  // --- "son durum" özeti: son 3 metin mesajı
  const texts = msgs.map((m, i) => ({ m, i })).filter((x) => x.m.content);
  if (texts.length) {
    const last = texts.slice(-3);
    const fmtD = (d) => new Date(d).toLocaleDateString("tr-TR", { timeZone: "Europe/Istanbul" });
    const body = `Son yazışma (${fmtD(last[last.length - 1].m.sent_at)}): ` + last.map((x) => `${x.m.role === "owner" ? "Siz" : x.m.role === "customer" ? "Müşteri" : (x.m.sender || "?")}: ${clip(squeeze(x.m.content), 140)}`).join(" | ");
    const idx = last[last.length - 1].i;
    const key = sha(`not|${idx}|son_durum`);
    if (!seen.has(key)) limited.push({ msgIndex: idx, kind: "not", payload: { body: clip(body, 600), tags: ["son_durum"], by: "system" }, confidence: 0.5, dedupeKey: key });
  }
  return limited.slice(0, MAX_TOTAL).sort((a, b) => a.msgIndex - b.msgIndex);
}

const uniq = (a) => [...new Set(a)];

module.exports = { extractSuggestions, MEAS_RE, PHONE_RE };
