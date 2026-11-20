/**
 * WhatsApp mesaj şablonları — SAF fonksiyonlar. LLM YOK, gönderim YOK: metin kodla doldurulur ve kullanıcıya
 * `wa.me` / `whatsapp://send` derin bağlantısı olarak verilir (kullanıcı kendi uygulamasında kendi eliyle gönderir; maliyet 0).
 *
 * Sözdizimi:
 *   {degisken}          değer yoksa yer tutucu OLDUĞU GİBİ kalır ve `missing` listesine girer
 *   {ilk_ad|e}          değişken + Türkçe hâl eki:  |e  |i  |de  |den  |in  |ile   ("Ahmet'e")
 *   {ad|upper} {ad|title}
 *   [[ … {x} … ]]       isteğe bağlı blok: içindeki herhangi bir değişken boşsa blok TAMAMEN atılır (eksik sayılmaz)
 */
const T = require("./turkish");

const MAX_VALUE_LEN = 300;
const MAX_TEXT_LEN = 4000;
const WA_URL_SOFT_LIMIT = 2000; // araştırma/tasarım §2.5.1: URL pratik sınırı ~2000 karakter [doğrulanmadı]

/** Belgelenen değişken kataloğu (API: GET /api/message-templates/variables) */
const VARIABLES = {
  ad: "Müşterinin tam adı (Baş Harfler Büyük)",
  ilk_ad: "Müşterinin ilk adı",
  firma_adi: "Firma adı (gövdeden, COMPANY_NAME ortam değişkeninden ya da defter sahibinin adından)",
  telefon: "Firma telefonu (gövdeden ya da COMPANY_PHONE)",
  iban_unvan: "Ödeme bilgisi metni (gövdeden ya da COMPANY_IBAN_INFO)",
  hizmet: "Hizmet / iş türü",
  proje_kodu: "Proje kodu (PRJ-…)",
  teklif_kodu: "Teklif kodu (OFR-…)",
  takip_linki: "Herkese açık teklif takip bağlantısı",
  tutar: "Tutar (TL) — teklif toplamı, taksit/fatura tutarı",
  kalan_tutar: "Kalan bakiye (TL)",
  vade_tarihi: "Vade tarihi (5 Aralık 2026)",
  fatura_no: "Fatura/belge numarası",
  tarih: "Randevu tarihi (5 Aralık 2026)",
  gun: "Randevu günü (Cumartesi)",
  saat: "Randevu saati (14:30)",
  randevu_turu: "Randevu türü (Keşif, Montaj …)",
  adres: "Adres",
  ret_notu: "İsteğe bağlı ret cümlesi (yalnız opt_out=true ise dolu)",
};

const TOKEN_RE = /\[\[|\]\]|\{([a-z0-9_]+)(?:\|([a-z]+))?\}/g;

/** Şablonu belirteçlere ayır: {type:'text'|'var'|'block'} */
function parse(body) {
  const root = []; const stack = [root];
  let last = 0; let m;
  TOKEN_RE.lastIndex = 0;
  const cur = () => stack[stack.length - 1];
  while ((m = TOKEN_RE.exec(body))) {
    if (m.index > last) cur().push({ t: "text", v: body.slice(last, m.index) });
    last = m.index + m[0].length;
    if (m[0] === "[[") { const blk = { t: "block", c: [] }; cur().push(blk); stack.push(blk.c); }
    else if (m[0] === "]]") { if (stack.length > 1) stack.pop(); else cur().push({ t: "text", v: "]]" }); }
    else cur().push({ t: "var", name: m[1], mod: m[2] || null });
  }
  if (last < body.length) cur().push({ t: "text", v: body.slice(last) });
  return root;
}

/** Şablondaki değişken adları (tekil, sıralı) */
function extractVars(body) {
  const names = new Set();
  (function walk(list) { for (const n of list) { if (n.t === "var") names.add(n.name); else if (n.t === "block") walk(n.c); } })(parse(String(body)));
  return [...names];
}

function applyMod(value, mod) {
  switch (mod) {
    case null: return value;
    case "upper": return T.upperTr(value);
    case "title": return T.titleCaseTr(value);
    case "e": case "i": case "de": case "den": case "in": case "ile": return T.suffix(value, mod);
    default: return value;
  }
}
const clean = (v) => String(v).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").slice(0, MAX_VALUE_LEN);
const filled = (v) => v !== undefined && v !== null && String(v).trim() !== "";

/**
 * Şablonu doldur. Değerler TEK GEÇİŞTE eklenir (eklenen değer yeniden yorumlanmaz).
 * @returns {{text:string, missing:string[], variables:string[], complete:boolean}}
 */
function renderTemplate(body, vars = {}) {
  const missing = new Set();
  function renderList(list, inBlock) {
    let out = ""; let dropped = false;
    for (const n of list) {
      if (n.t === "text") out += n.v;
      else if (n.t === "var") {
        if (filled(vars[n.name])) out += applyMod(clean(vars[n.name]).trim(), n.mod);
        else if (inBlock) dropped = true;
        else { missing.add(n.name); out += `{${n.name}${n.mod ? "|" + n.mod : ""}}`; }
      } else {
        const r = renderList(n.c, true);
        if (!r.dropped) out += r.out;
      }
    }
    return { out, dropped };
  }
  const text = renderList(parse(String(body)), false).out.replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim().slice(0, MAX_TEXT_LEN);
  return { text, missing: [...missing], variables: extractVars(body), complete: missing.size === 0 };
}

/**
 * Telefon → WhatsApp için ülke kodlu rakam dizisi (ör. 0532… → 90532…). Geçersizse null.
 * Kurallar: "00" ön eki → uluslararası; "0" ile başlayan → Türkiye (90); 10 haneli → Türkiye; "90" + 10 hane; "+" varsa E.164 olduğu gibi.
 * Mevcut services/whatsapp.js normalizePhone ile ortak girdilerde aynı sonucu verir; ek olarak geçersiz numarayı null döner.
 */
function normalizePhone(phone) {
  if (phone === null || phone === undefined) return null;
  const raw = String(phone).trim();
  if (raw.length > 40) return null;
  const plus = raw.startsWith("+");
  let d = raw.replace(/\D/g, "");
  if (!d) return null;
  if (d.startsWith("00")) d = d.slice(2);
  else if (!plus && d.startsWith("0")) d = "90" + d.slice(1);
  else if (!plus && d.length === 10) d = "90" + d;
  if (d.startsWith("90")) return d.length === 12 && /^90[1-9]\d{9}$/.test(d) ? d : null;
  return d.length >= 8 && d.length <= 15 && !d.startsWith("0") ? d : null;
}

/** wa.me ve whatsapp:// bağlantıları. Telefon geçersizse null alanlar döner. text URL-kodlanır (UTF-8). */
function buildWhatsAppLinks(phone, text) {
  const digits = normalizePhone(phone);
  const q = encodeURIComponent(String(text ?? ""));
  if (!digits) return { phone: null, whatsappUrl: null, whatsappAppUrl: null, urlTooLong: false };
  const whatsappUrl = `https://wa.me/${digits}?text=${q}`;
  return { phone: digits, whatsappUrl, whatsappAppUrl: `whatsapp://send?phone=${digits}&text=${q}`, urlTooLong: whatsappUrl.length > WA_URL_SOFT_LIMIT };
}

/**
 * Ham varlıklardan değişken sözlüğü üretir (DB'den bağımsız → birim test edilebilir).
 * ctx: {firma_adi, telefon, iban_unvan, siteUrl, optOut, customer:{name,phone}, offer:{code,name,phone,service,tracking_code}, quoteTotalKurus,
 *       project:{code,customer_name,service}, remainingKurus, schedule:{amount_kurus,due_date}, invoice:{invoice_no,odenecek_kurus,due_date},
 *       appointment:{scheduled_at,type,address,customer_name,customer_phone}}
 * Öncelik (alt kaynak üst kaynağı ezer): müşteri < teklif < proje < randevu; tutar/vade: plan satırı > fatura > teklif toplamı.
 */
function buildVars(ctx = {}) {
  const v = {};
  const set = (k, val) => { if (filled(val)) v[k] = String(val); };
  set("firma_adi", ctx.firma_adi); set("telefon", ctx.telefon); set("iban_unvan", ctx.iban_unvan);
  let phone = null;
  const c = ctx.customer, o = ctx.offer, p = ctx.project, a = ctx.appointment;
  if (c) { set("ad", c.name && T.titleCaseTr(c.name)); phone = c.phone || phone; set("adres", c.address); }
  if (o) {
    set("ad", o.name && T.titleCaseTr(o.name)); phone = o.phone || phone; set("hizmet", o.service); set("teklif_kodu", o.code);
    if (o.tracking_code && ctx.siteUrl) set("takip_linki", `${String(ctx.siteUrl).replace(/\/+$/, "")}/teklif-takip/${o.tracking_code}`);
    set("adres", o.address);
  }
  if (Number.isInteger(ctx.quoteTotalKurus)) set("tutar", T.formatTL(ctx.quoteTotalKurus));
  if (p) { set("ad", p.customer_name && T.titleCaseTr(p.customer_name)); set("hizmet", p.service); set("proje_kodu", p.code); set("adres", p.address); }
  if (Number.isInteger(ctx.remainingKurus)) set("kalan_tutar", T.formatTL(ctx.remainingKurus));
  if (ctx.invoice) {
    set("fatura_no", ctx.invoice.invoice_no);
    if (Number.isInteger(ctx.invoice.odenecek_kurus)) set("tutar", T.formatTL(ctx.invoice.odenecek_kurus));
    if (ctx.invoice.due_date) set("vade_tarihi", T.formatDateTr(ctx.invoice.due_date));
  }
  if (ctx.schedule) {
    if (Number.isInteger(ctx.schedule.amount_kurus)) set("tutar", T.formatTL(ctx.schedule.amount_kurus));
    if (ctx.schedule.due_date) set("vade_tarihi", T.formatDateTr(ctx.schedule.due_date));
  }
  if (a) {
    set("ad", a.customer_name && T.titleCaseTr(a.customer_name)); phone = a.customer_phone || phone; set("randevu_turu", a.type); set("adres", a.address);
    if (a.scheduled_at) {
      const when = new Date(a.scheduled_at);
      const day = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul", year: "numeric", month: "2-digit", day: "2-digit" }).format(when);
      const time = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Istanbul", hour: "2-digit", minute: "2-digit", hour12: false }).format(when);
      set("tarih", T.formatDateTr(day)); set("gun", T.weekdayTr(day)); set("saat", time);
    }
  }
  if (v.ad) set("ilk_ad", T.firstName(v.ad));
  if (ctx.optOut) set("ret_notu", "Bu bildirimleri almak istemiyorsanız DUR yazabilirsiniz.");
  // Gövdeden gelen açık değerler (ctx.override) her şeyi ezer
  for (const [k, val] of Object.entries(ctx.override || {})) if (k in VARIABLES) set(k, val);
  return { vars: v, phone: ctx.phoneOverride || phone };
}

module.exports = { VARIABLES, parse, extractVars, renderTemplate, normalizePhone, buildWhatsAppLinks, buildVars, WA_URL_SOFT_LIMIT };
