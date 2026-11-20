/**
 * Kural tabanlı Türkçe KOMUT ÇUBUĞU ayrıştırıcısı. Saf fonksiyon: parseCommand(text, {now, candidates}).
 * Çıktı SABİT yapı: {intent, params, confidence, ambiguities[]}. LLM yoktur; veritabanına dokunmaz.
 *
 * Niyetler:
 *  yazma  : appointment.create | appointment.reschedule | appointment.cancel | reminder.create | payment.add |
 *           expense.add | offer.status | note.add
 *  okuma  : query.agenda | query.appointments | query.collections | query.expenses | query.receivables | customer.search
 *  yasak  : forbidden (params.reason = delete | role_change | send_message | amount_change)  — hiçbir zaman çalıştırılmaz
 *  diğer  : unknown
 * ambiguities[i] = {field, kind, options?}; kind: missing | multiple | not_found | ampm | assumed | vague | same_weekday | default
 */
const { clean, fold } = require("./text");
const { tokenize, remainder } = require("./tokenize");
const { parseDateTime, addDays, addMonths, todayOf, toISO, istParts, ymd, daysInMonth, weekdayOf, MONTHS, WD_RE } = require("./datetime");
const { extractAmount, readWordNumber } = require("./numbers");
const { prepareCandidates, matchCustomers, decide, guessQuery, HONORIFIC_RE, RESERVED, SUFFIX_SET } = require("./entities");

const MAX_TEXT = 500;

const OFFER_STATUSES = {
  kabul: "Kabul Edildi", red: "Reddedildi", incelendi: "İncelendi", kesif: "Keşif Planlandı", verildi: "Teklif Verildi", yeni: "Yeni",
};

const APPT_TYPES = [
  [/\b(kesif\w*|olcu\w*|olcum\w*|kesfe)\b/, "kesif"],
  [/\b(montaj\w*|kurulum\w*|takma|takilma)\b/, "montaj"],
  [/\bteslim\w*\b/, "teslim"],
  [/\b(servis\w*|bakim\w*|tamir\w*|ariza\w*)\b/, "servis"],
  [/\b(gorusme\w*|toplanti\w*|bulusma\w*|gorus\w*)\b/, "gorusme"],
];

const R = {
  del: /\b(sil|silin|silsene|silelim|sileyim|silmek|silsin|sildir|kaldir|kaldirin|kaldirsana|yok et|temizle|temizlesene|ucur|imha et|delete|drop|remove|truncate|destroy|wipe)\b/,
  role: /\b(yetki\w*|rol|rolu|rolunu|rolunun|sifre|sifresini|sifremi|kullanici (ekle|olustur|yap|sil)|admin yap|yonetici yap|admin olarak|yonetici olarak)\b/,
  sendObj: /\b(mesaj\w*|whatsapp\w*|watsap\w*|vatsap\w*|sms\w*|mail\w*|e posta\w*|eposta\w*|teklif\w*|fatura\w*|pdf\w*|dekont\w*|bilgilendirme\w*)\b/,
  sendVerb: /\b(gonder|gonderin|gondersene|gonderelim|gonderir misin|gonderebilir misin|gonderiver|yolla|yollar misin|yollayin|yollasana|ilet|iletin|iletsene|at|atin|atsana|atar misin|ativer|yaz|yazsana|yazin|ulastir)\b/,
  amountChange: /\b(teklif\w*|ofr|prj|sozlesme\w*|proje\w*|fatura\w*)\b.*\btutar\w*\b.*\b(degistir\w*|guncelle\w*|duzenle\w*|duzelt\w*|arttir\w*|dusur\w*|indir\w*|yap|olsun|yukselt\w*)\b|\btutar\w*\b.*\b(degistir\w*|guncelle\w*|duzenle\w*)\b.*\b(teklif\w*|ofr|prj|sozlesme\w*|proje\w*)\b/,
  remind: /\bhatirla(t|tma|tir|tici|tin)/,
  writeVerb: /\b(ekle|ekleyin|eklesene|eklermisin|ekler misin|gir|girin|girsene|kaydet|kaydedin|isle|olustur|olusturun|koy|koyun|kur|ayarla|ayarlayin|yaz|planla|planlayin)\b/,
  qWords: /\b(ne kadar|kac|kimden|kimler|kimlerden|hangi|neler|ne var|var mi|varmi|listele|goster|listesi|toplam|durumu|nedir|ne kadarmis|kalan|var|ne|mi|mu)\b/,
  collect: /\b(tahsilat\w*|tahsil\w*|kasaya|kasa|gelir\w*|ciro\w*|para girdi|girdi|giren)\b/,
  expense: /\b(gider\w*|masraf\w*|harcama\w*|harcad\w*)\b/,
  payment: /\b(odeme\w*|tahsilat\w*|tahsil\w*|havale\w*|eft|odedi|odediler|yatirdi|yatirmis|yatirmislar|getirdi|birakti|verdi|vermis|aldim|aldik|cekti)\b/,
  paymentPast: /\b(odedi|odediler|yatirdi|yatirmis|getirdi|birakti|verdi|vermis|aldim|aldik|cekti|tahsil ettim|tahsil ettik|tahsil edildi)\b/,
  expensePast: /\b(odedim|odedik|harcadim|harcadik|verdim|verdik|aldim)\b/,
  receivable: /\b(alacak\w*|alacag\w*|borc\w*|bakiye\w*|odemeyen\w*|odenmemis|tahsil edilmemis|geciken odeme\w*|geciken tahsilat\w*|bekleyen odeme\w*|kalan odeme\w*)\b/,
  apptAcc: /\b(randevuyu|randevusunu|randevumu|randevumuzu|kesfi|kesfini|kesfimi|montaji|montajini|gorusmeyi|gorusmesini|toplantiyi)\b/,
  apptNoun: /\b(randevu\w*|kesif\w*|montaj\w*|olcu\w*|gorusme\w*|toplanti\w*|bulusma\w*)\b/,
  resched: /\b(ertele\w*|erteler\w*|kaydir\w*|tasi\w*|one al\w*|ileri al\w*|geri al\w*|degistir\w*|guncelle\w*|alalim|alabilir miyiz|alsana|alin)\b/,
  cancel: /\b(iptal\w*|vazgec\w*|vazgectik|bosalt\w*)\b/,
  offer: /\b(teklif\w*|ofr)\b/,
  periodWords: /\b(bugun|bugunun|bu gun|yarin|bu hafta|haftaya|bu ay|gecen ay|gecen hafta|bu yil|geceen|gelecek ay|gecen yil|bu sene|hafta|ay)\b/,
};

const METHODS = [
  [/\b(havale\w*|eft|fast|banka\w*|iban|dekont\w*)\b/, "Havale"],
  [/\b(nakit\w*|elden|cash|pesin\w*|el ile)\b/, "Nakit"],
  [/\b(kredi karti|kredi kart\w*|kart\w*|pos|visa|master\w*|taksit\w*)\b/, "Kredi Kartı"],
];

const GLUE = new Set(["bana", "diye", "lutfen", "bir", "ve", "icin", "olarak", "kur", "ekle", "olustur", "yap", "yapar", "misin", "mi", "mu", "bunu", "su", "sunu", "tekrar", "ayarla", "kaydet", "gir", "yaz", "koy", "bi", "bakar", "rica", "ederim", "tesekkurler", "tamam", "hemen"]);

/** Aday listesini bir kez hazırla (aynı dizi için önbellek) */
const prepCache = new WeakMap();
function prep(list) {
  if (!list) return [];
  if (prepCache.has(list)) return prepCache.get(list);
  const p = prepareCandidates(list);
  prepCache.set(list, p);
  return p;
}

function parseCommand(text, ctx = {}) {
  const now = ctx.now ? new Date(ctx.now) : new Date();
  const result = (intent, params = {}, confidence = 0, ambiguities = []) => ({ intent, params, confidence: Math.round(confidence * 100) / 100, ambiguities });
  if (typeof text !== "string" || !text.trim()) return result("unknown", {}, 0, [{ field: "text", kind: "missing" }]);
  const raw = clean(text).trim();
  if (raw.length > MAX_TEXT) return result("unknown", { reason: "too_long" }, 0);

  const tokens = tokenize(raw);
  const words = raw.split(/\s+/).filter(Boolean);
  const norm = tokens.map((t) => t.t).join(" ");
  const has = (re) => re.test(norm);
  const cands = prep(ctx.candidates);

  // ===== 1) YASAKLI niyetler (R3): silme, yetki/rol değişimi, mesaj gönderme, tutar değiştirme =====
  const sendStatus = /\b(gonderildi|gonderdim|gonderdik|gonderilmis|iletildi|iletildi)\b/.test(norm);
  // "not ekle Ahmet Yılmaz: <serbest metin>" — iki noktadan SONRAKİ gövde yalnız metin olarak saklanır (hiçbir komut çalıştırmaz);
  // yasaklı fiil taraması yalnız komut kısmına (iki nokta öncesine) uygulanır.
  const noteHead = /^\s*(\S+\s+){0,3}not(u|um)?\s*(ekle|al|dus|yaz|tut|kaydet|birak)?\s*[^:]*:/i.test(fold(raw)) ? fold(raw.slice(0, raw.indexOf(":"))).replace(/['’‘`´ʼ]/g, " ") : null;
  const hasF = (re) => (noteHead !== null ? re.test(noteHead) : has(re));
  if (hasF(R.del) && !/\b(sildim|silindi)\b/.test(norm)) return result("forbidden", { reason: "delete" }, 0.95);
  if (hasF(R.role) && !/\b(rol|yetki)\b.*\b(not|hatirlat)\b/.test(norm)) {
    if (/\b(ver|verin|degistir\w*|yap|ata|atayin|ekle|sifirla\w*|guncelle\w*|ac|kapat|kaldir\w*|olustur|ayarla|artir|arttir)\b/.test(norm) || /^(yetki|rol|sifre)/.test(norm)) return result("forbidden", { reason: "role_change" }, 0.93);
  }
  if (hasF(R.sendObj) && hasF(R.sendVerb) && !sendStatus && !/\bnot\b/.test(norm)) {
    // "teklif durumu gönderildi yap" gibi durum değişikliği hariç (sendStatus); "teklifi gönder" yasak
    if (!/\b(durum\w*|isaretle|olarak yap)\b/.test(norm) || /\b(mesaj|whatsapp|sms|mail)\b/.test(norm)) return result("forbidden", { reason: "send_message" }, 0.93);
  }
  if (noteHead !== null ? R.amountChange.test(noteHead) : R.amountChange.test(norm)) return result("forbidden", { reason: "amount_change" }, 0.9);

  const used = new Set();
  const amb = [];

  // ===== 2) Müşteri eşleme — faz A (tam ad: tarih sözcüğü adın parçası olabilsin) =====
  let hitsA = cands.length ? matchCustomers(tokens, used, cands, { phase: "full" }) : [];
  const posA = new Set(hitsA.flatMap((h) => h.positions));

  // ===== 3) Niyet sınıfı =====
  const hasRemind = has(R.remind);
  const noteIdx = tokens.findIndex((t, i) => (t.t === "not" || t.t === "notu" || t.t === "notum") && !(i > 0 && /^(teklif|proje|odeme)$/.test(tokens[i - 1].t) && false));
  const noteVerbNext = noteIdx >= 0 && /^(ekle|al|dus|yaz|tut|kaydet|birak|olarak|ver|ekleyin|alin|alsana|dusun|dusur)$/.test(tokens[noteIdx + 1]?.t || "");
  const noteStart = noteIdx === 0 || (noteIdx > 0 && (noteVerbNext || tokens[noteIdx].punct.includes(":") || tokens[noteIdx + 1]?.punct?.includes(":") || /^(icin|e|a|ye|ya|ne|na)$/.test(tokens[noteIdx - 1]?.t || "")));
  const isNote = noteIdx >= 0 && noteStart && !hasRemind && !(noteIdx > 0 && /^(teklif|proje)$/.test(tokens[noteIdx - 1].t));
  const hasAppt = has(R.apptNoun);
  const hasResched = has(R.resched) || (has(R.apptAcc) && /\b(al|alalim|alsak|alin|alsana)\b/.test(norm));
  const hasCancel = has(R.cancel);
  const writeVerb = has(R.writeVerb);
  const offerCodeEarly = tokens.some((t) => /^ofr-\d+$/i.test(t.o));
  const dativeTimeNeeded = hasResched && (hasAppt || cands.length > 0);

  // zaman ayrıştırma (jeton tüketimi sırası önemli): seçici ("yarınki randevu") → tarih → tutar → müşteri(any)
  let selectorDate = null;
  if (hasResched || hasCancel) {
    for (let i = 0; i < tokens.length; i++) {
      const s = tokens[i].t;
      if (/^(yarinki|bugunku|dunku)$/.test(s) && !posA.has(i)) { selectorDate = addDays(todayOf(now), s === "yarinki" ? 1 : s === "dunku" ? -1 : 0); used.add(i); break; }
      // "pazartesi günkü randevu": hafta günü + "günkü" → hedef randevu tarihi (yeni tarih değil)
      const wdm = WD_RE.exec(s);
      if (wdm && /^(gunku|gunkunu|gunlu)$/.test(tokens[i + 1]?.t || "") && !posA.has(i)) {
        const wdIdx = { pazartesi: 0, sali: 1, carsamba: 2, persembe: 3, cuma: 4, cumartesi: 5, pazar: 6 }[wdm[1]];
        const tw = weekdayOf(todayOf(now));
        selectorDate = addDays(todayOf(now), ((wdIdx - tw + 7) % 7) || 7);
        used.add(i); used.add(i + 1); break;
      }
    }
  }
  // "3 gün ertele" / "bir hafta ertele" → öteleme günü
  let shiftDays = null;
  if (hasResched) {
    for (let i = 0; i < tokens.length - 1; i++) {
      const rn = numAtTok(tokens, i);
      if (rn && /^(gun|hafta)$/.test(tokens[i + rn.len]?.t || "") && /^(ertele|erteleyin|ileri|one|kaydir|kaydirin|ote|otele|otelesin|ertelensin|alin|al)/.test(tokens[i + rn.len + 1]?.t || "") && !used.has(i)) {
        shiftDays = rn.v * (tokens[i + rn.len].t === "hafta" ? 7 : 1);
        for (let k = i; k < i + rn.len + 1; k++) used.add(k);
        break;
      }
    }
  }
  for (const p of posA) used.add(p);

  const dt = parseDateTime(tokens, used, now, { dativeTime: dativeTimeNeeded, assumeDateFromTime: !hasResched });
  const amountOpts = { allowBare: !hasAppt || has(R.payment) || has(R.expense) };
  const amt = extractAmount(tokens, used, amountOpts);
  if (amt) for (let k = amt.idx[0]; k < amt.idx[1]; k++) used.add(k);
  // faz B: tek jeton eşleşmeleri
  const hitsB = cands.length ? matchCustomers(tokens, used, cands, { phase: "any" }) : [];
  let hitsAll = dedupeHits([...hitsA, ...hitsB]);
  const usedNoName = new Set([...used].filter((i) => !posA.has(i)));

  // Müşteri kararı (belirsizlik, bulunamadı)
  const resolveCustomer = () => {
    if (hitsAll.length) {
      const d = decide(hitsAll.map((h) => ({ ...h })));
      d.positions.forEach((p) => used.add(p));
      // unvan jetonlarını da tüket ("Bey", "Hanım")
      d.positions.forEach((p) => { for (const q of [p + 1, p + 2]) { if (tokens[q] && !used.has(q) && HONORIFIC_RE.test(tokens[q].t)) used.add(q); } });
      // yanlış soyad uyarısı: ilk ad eşleşti ama yanında büyük harfli tanımsız bir sözcük var → "bulunamadı"
      if (d.matched) {
        const top = hitsAll.find((h) => h.cand.key === d.matched.key);
        if (top && !top.full && top.positions.length === 1) {
          const nx = tokens[top.positions[0] + 1];
          if (nx && nx.cap && !used.has(top.positions[0] + 1) && !RESERVED.has(nx.t) && !HONORIFIC_RE.test(nx.t) && /^[a-zçğıöşü]{3,}$/i.test(nx.o) && !/^(OFR|PRJ)/i.test(nx.o)) {
            const g = hitsAll.filter((h) => top.cand._toks[0] === h.cand._toks[0]);
            used.add(top.positions[0] + 1);
            return { query: tokens[top.positions[0]].o + " " + nx.o, matched: null, candidates: g.slice(0, 5).map((h) => ({ key: h.cand.key, name: h.cand.name, phone: h.cand.phone || null, score: 0.5 })), notFound: true };
          }
        }
      }
      const qpos = d.positions.length ? d.positions : hitsAll[0].positions;
      const query = qpos.sort((a, b) => a - b).map((p) => tokens[p].o).join(" ");
      return { query, ...d };
    }
    const g = guessQuery(tokens, used);
    if (g) { g.idx.forEach((k) => used.add(k)); return { query: g.query, matched: null, candidates: [], notFound: true }; }
    return null;
  };
  const customerOut = (c) => (c ? { query: c.query, match: c.matched || null, candidates: c.candidates || [] } : { query: null, match: null, candidates: [] });
  const custAmb = (c, required) => {
    if (!c) { if (required) amb.push({ field: "customer", kind: "missing" }); return; }
    if (c.notFound) amb.push({ field: "customer", kind: "not_found", options: c.candidates });
    else if (!c.matched && c.candidates.length) amb.push({ field: "customer", kind: "multiple", options: c.candidates });
  };
  const dtAmb = () => { for (const a of dt.ambiguities) amb.push(a); if (dt.vague) amb.push({ field: "date", kind: "vague" }); };
  const atOf = () => (dt.date && dt.time ? toISO(dt.date, dt.time) : null);

  // ===== 4) NOT =====
  if (isNote) {
    const k = noteIdx;
    let start = k + 1;
    if (/^(ekle|al|dus|yaz|tut|kaydet|birak|olarak|ver|ekleyin|alin|alsana|dusun|dusur)$/.test(tokens[start]?.t || "")) start++;
    const colonDirect = tokens[start - 1].punct.includes(":");
    const colonTok = tokens.findIndex((t, i) => i >= start && t.punct.includes(":"));
    const beforeHits = hitsAll.filter((h) => h.positions.every((p) => p < k));
    const afterHits = hitsAll.filter((h) => h.positions.every((p) => p >= start));
    const isNameTok = (m) => hitsAll.some((h) => h.positions.includes(m)) || HONORIFIC_RE.test(tokens[m].t);
    const skipName = (m) => { while (m < tokens.length && (isNameTok(m) || (m > 0 && isNameTok(m - 1) && SUFFIX_SET.has(tokens[m].t)))) m++; return m; };
    let customer = null, textFrom = start;
    if (beforeHits.length) {
      customer = { query: tokens[beforeHits[0].positions[0]].o, ...decide(beforeHits.map((h) => ({ ...h }))) };
    } else if (colonDirect) {
      if (afterHits.length) customer = { query: tokens[afterHits[0].positions[0]].o, ...decide(afterHits.map((h) => ({ ...h }))) };
    } else if (colonTok >= start && afterHits.some((h) => h.positions.every((p) => p <= colonTok))) {
      const hs = afterHits.filter((h) => h.positions.every((p) => p <= colonTok));
      customer = { query: tokens.slice(start, colonTok + 1).map((t) => t.o).join(" "), ...decide(hs.map((h) => ({ ...h }))) };
      textFrom = colonTok + 1;
    } else if (colonTok >= start && colonTok - start <= 3 && tokens.slice(start, colonTok + 1).every((t) => /^[a-zçğıöşü]+$/i.test(t.o)) && tokens.slice(start, colonTok + 1).some((t) => t.cap || HONORIFIC_RE.test(t.t))) {
      customer = { query: tokens.slice(start, colonTok + 1).map((t) => t.o).join(" "), matched: null, candidates: [], notFound: true };
      textFrom = colonTok + 1;
    } else if (afterHits.some((h) => Math.min(...h.positions) === start)) {
      const hs = afterHits.filter((h) => Math.min(...h.positions) === start);
      customer = { query: tokens[start].o, ...decide(hs.map((h) => ({ ...h }))) };
      textFrom = skipName(start);
    }
    const textTok = tokens.slice(textFrom);
    let txt = textTok.length ? words.slice(textTok[0].wi).join(" ") : "";
    // iki noktadan sonra kalan metin: sözcük içindeki "ad:" biçimi için ilk sözcükte baştaki noktalama atılır
    txt = txt.replace(/^[\s:\-–—]+/, "").trim();
    if (!txt) amb.push({ field: "text", kind: "missing" });
    custAmb(customer, false);
    return result("note.add", { text: txt || null, customer: customerOut(customer) }, txt ? 0.9 : 0.5, amb);
  }

  // ===== 5) HATIRLATMA =====
  if (hasRemind) {
    const c = resolveCustomerSoft();
    // başlık: kullanılmayan jetonlar; tetikleyici/yapıştırıcı sözcükler çıkarılır
    let title = remainder(tokens, usedNoName, (tk) => /^(hatirla\w*|bana|beni|diye|lutfen|kur|olustur|ekle|ayarla|kaydet)$/.test(tk.t));
    title = cleanTitle(title);
    // müşteri adı başlıkta kalsın (kullanıcı yazdığı gibi): customer ayrı da raporlanır
    if (!title) amb.push({ field: "title", kind: "missing" });
    if (!dt.hasDate && !dt.hasTime) amb.push({ field: "when", kind: "missing" });
    else if (dt.hasDate && !dt.hasTime) { amb.push({ field: "time", kind: "default", value: "09:00" }); dt.time = "09:00"; dt.hasTime = true; }
    dtAmb();
    if (c) custAmb(c, false);
    return result("reminder.create", { title: title || null, date: dt.date, time: dt.time, at: atOf(), customer: customerOut(c) }, 0.92 - 0.05 * amb.filter((a) => a.kind !== "default").length, amb);
  }

  // ===== 6) RANDEVU ERTELE / İPTAL =====
  if (hasAppt && hasCancel && !writeVerb || (hasCancel && cands.length && hitsAll.length && !hasResched && !has(R.expense) && !has(R.payment) && !has(R.offer))) {
    const c = resolveCustomer();
    custAmb(c, false);
    if (!c && !selectorDate && !dt.hasDate) amb.push({ field: "target", kind: "missing" });
    return result("appointment.cancel", { customer: customerOut(c), date: selectorDate || dt.date }, 0.9 - 0.05 * amb.length, amb);
  }
  if (hasResched && (hasAppt || selectorDate || (hitsAll.length && !has(R.offer) && !has(R.expense) && !has(R.payment) && !offerCodeEarly))) {
    const c = resolveCustomer();
    custAmb(c, false);
    if (!c && !selectorDate) amb.push({ field: "target", kind: "missing" });
    if (!dt.hasDate && !dt.hasTime && shiftDays === null) amb.push({ field: "when", kind: "missing" });
    dtAmb();
    const params = { customer: customerOut(c), target_date: selectorDate, new_date: dt.date, new_time: dt.time, shift_days: shiftDays };
    if (dt.date && dt.time) params.at = atOf();
    return result("appointment.reschedule", params, 0.9 - 0.05 * amb.filter((a) => a.kind !== "assumed").length, amb);
  }

  // ===== 7) TEKLİF DURUMU =====
  const offerCode = (tokens.find((t) => /^ofr-\d+$/i.test(t.o)) || {}).o;
  const statusOf = () => {
    if (/\b(kabul\w*|onayla\w*|onaylandi|onay\w*|kazandik|kazandi|alindi)\b/.test(norm) && !/\b(kabul etmedi|onaylamadi)\b/.test(norm)) return OFFER_STATUSES.kabul;
    if (/\b(red\w*|olumsuz|kaybettik|kaybedildi|vazgecti|vazgectiler|kabul etmedi|onaylamadi)\b/.test(norm)) return OFFER_STATUSES.red;
    if (/\bkesif planlandi\b|\bkesif planla\w*\b/.test(norm) && !/\brandevu\b/.test(norm)) return OFFER_STATUSES.kesif;
    if (/\b(incelendi|inceledim|inceleme)\b/.test(norm)) return OFFER_STATUSES.incelendi;
    if (/\b(teklif verildi|teklif verdim|teklifi verdim|teklif gonderildi|gonderildi|gonderdim|iletildi|teklif iletildi|teklif hazirlandi)\b/.test(norm)) return OFFER_STATUSES.verildi;
    if (/\b(yeni durumuna|yeni olarak|yeniye)\b/.test(norm)) return OFFER_STATUSES.yeni;
    return null;
  };
  if ((has(R.offer) || offerCode) && !has(R.expense) && !(has(R.payment) && amt)) {
    const st = statusOf();
    if (st || /\bdurum\w*\b/.test(norm) && !has(R.qWords) || offerCode) {
      if (!(has(R.qWords) && /\b(ne kadar|kac|kimler|hangi|listele|goster)\b/.test(norm)) || st) {
        const c = resolveCustomer();
        custAmb(c, false);
        if (!st) amb.push({ field: "status", kind: "missing" });
        if (!c && !offerCode) amb.push({ field: "offer", kind: "missing" });
        return result("offer.status", { status: st, offer_ref: offerCode ? offerCode.toUpperCase() : null, customer: customerOut(c) }, 0.9 - 0.05 * amb.length, amb);
      }
    }
  }

  // ===== 8) GİDER =====
  const expenseWords = has(R.expense);
  const expenseVerb = has(R.expensePast) && amt && !hasAppt && !(hitsAll.length && has(R.payment) && !/\bodedim|odedik\b/.test(norm));
  if ((expenseWords || expenseVerb) && !has(R.receivable)) {
    const isQuery = !amt && (/\b(ne kadar|kac|toplam|listele|goster|listesi|nedir|ne tutuyor|ne oldu)\b/.test(norm)) && !writeVerb;
    if (isQuery) {
      const per = resolvePeriod(tokens, norm, now, used, dt);
      return result("query.expenses", { period: per.period, from: per.from, to: per.to }, 0.9, per.amb);
    }
    const c = resolveCustomerSoft();
    let scope = "genel";
    const scopeUsed = new Set();
    tokens.forEach((tk, i) => { if (used.has(i)) return; if (/^(dukkan|dukkanin|dukkana|magaza|atolye|isyeri|ofis)$/.test(tk.t)) { scope = "dukkan"; scopeUsed.add(i); } else if (/^(ev|evin|eve|evde|kisisel|ozel)$/.test(tk.t)) { scope = "ev"; scopeUsed.add(i); } else if (tk.t === "genel") { scopeUsed.add(i); } });
    scopeUsed.forEach((i) => used.add(i));
    let cat = remainder(tokens, used, (tk) => GLUE.has(tk.t) || /^(gider\w*|masraf\w*|harcama\w*|harcadim|harcadik|odedim|odedik|verdim|verdik|aldim|tl|lira|girdim|ekle|proje\w*|projesine|projesi|icin|ile|bin|nin|nun|in|un|i|u|e|a|ye|ya|den|dan)$/.test(tk.t) || /^(tl|lira)$/.test(tk.t));
    cat = canonCategory(cat);
    if (!amt) amb.push({ field: "amount", kind: "missing" });
    if (c) custAmb(c, false);
    dtAmb();
    const projectRef = (tokens.find((t) => /^prj-\d+$/i.test(t.o)) || {}).o;
    return result("expense.add", { amount: amt ? amt.value : null, category: cat || null, scope, customer: customerOut(c), project_ref: projectRef ? projectRef.toUpperCase() : null, date: dt.hasDate ? dt.date : null }, 0.9 - 0.05 * amb.filter((a) => a.kind !== "assumed").length, amb);
  }

  // ===== 9) ÖDEME / TAHSİLAT (yazma) =====
  const payWords = has(R.payment);
  const collectQuery = has(R.collect) && !amt && !writeVerb && (has(R.qWords) || has(R.periodWords)) && !/\b(ekle|gir|kaydet)\b/.test(norm);
  if (payWords && !collectQuery && !has(R.receivable) && !(has(R.qWords) && !amt && /\b(kimden|kimler|kimlerden|hangi)\b/.test(norm))) {
    if (amt || writeVerb || hitsAll.length || has(R.paymentPast)) {
      const c = resolveCustomer();
      let method = null;
      for (const [re, m] of METHODS) if (re.test(norm)) { method = m; break; }
      if (!amt) amb.push({ field: "amount", kind: "missing" });
      const projRefEarly = tokens.some((t) => /^prj-\d+$/i.test(t.o));
      custAmb(c, !projRefEarly);
      if (!method) amb.push({ field: "method", kind: "default", value: "Nakit", options: ["Nakit", "Havale", "Kredi Kartı"] });
      dtAmb();
      const projectRef = (tokens.find((t) => /^prj-\d+$/i.test(t.o)) || {}).o;
      return result("payment.add", { amount: amt ? amt.value : null, method: method || "Nakit", customer: customerOut(c), project_ref: projectRef ? projectRef.toUpperCase() : null, date: dt.hasDate ? dt.date : null }, 0.9 - 0.05 * amb.filter((a) => !["default", "assumed"].includes(a.kind)).length, amb);
    }
  }

  // ===== 10) SORGULAR =====
  if (has(R.receivable) || (/\bkimden\b/.test(norm) && /\balacag\w*|\balacak\w*|\bborc\w*/.test(norm))) {
    const c = resolveCustomerSoft();
    if (c) custAmb(c, false);
    return result("query.receivables", { customer: customerOut(c) }, 0.92, amb);
  }
  if (has(R.collect) && !amt) {
    const per = resolvePeriod(tokens, norm, now, used, dt);
    return result("query.collections", { period: per.period, from: per.from, to: per.to }, 0.92, per.amb);
  }
  const createVerb = /\b(ekle\w*|koy\w*|ver|verin|olustur\w*|ayarla\w*|planla\w*|al|alalim|alin|kaydet\w*|yap|yapalim|yapin|kur\w*|belirle\w*|ac|acin)\b/.test(norm);
  const apptQueryForm = /\b(randevular\w*|randevum\b|var mi|varmi|listele\w*|liste\w*|goster\w*|kac|hangi|ne zaman|ne kadar)\b/.test(norm) || (dt.hasDate && !hitsAll.length && !dt.hasTime);
  if (/\b(randevu\w*)\b/.test(norm) && !writeVerb && !createVerb && !hasResched && apptQueryForm) {
    const per = resolvePeriod(tokens, norm, now, used, dt, { defaultPeriod: "today" });
    const c = resolveCustomerSoft();
    if (c) custAmb(c, false);
    if (c && !dt.hasDate && !/\b(bugun|yarin|hafta|haftaya|ay|gelecek|gecen)\b/.test(norm)) { per.period = "upcoming"; per.from = todayOf(now); per.to = null; }
    return result("query.appointments", { period: per.period, from: per.from, to: per.to, customer: customerOut(c) }, 0.9, per.amb);
  }
  if (/\b(ne var|neler var|neler|ne yapacagim|ne yapmam gerek\w*|ne yapmaliyim|ne yapicam|program\w*|plan\w*|gundem\w*|isler\w*|isim|islerim|is listesi|gorev\w*|yapilacak\w*)\b/.test(norm) && (dt.hasDate || /\b(bugun|bugunun|yarin|hafta|haftaya|gun|gunun)\b/.test(norm) || /^(ne var|neler var)/.test(norm)) && !writeVerb) {
    const per = resolvePeriod(tokens, norm, now, used, dt, { defaultPeriod: "today" });
    return result("query.agenda", { period: per.period, from: per.from, to: per.to }, 0.9, per.amb);
  }

  // ===== 11) RANDEVU OLUŞTUR =====
  if (hasAppt && (writeVerb || /\b(ekle\w*|koy\w*|olustur\w*|ayarla\w*|planla\w*|ver\w*|al|alalim|alin|kaydet\w*|yap\w*|kur\w*|belirle\w*)\b/.test(norm) || hitsAll.length || dt.hasDate || dt.hasTime) && !/\b(ne|kac|hangi|listele|goster|var mi|varmi)\b/.test(norm.replace(/\bne zaman\b/, ""))) {
    const c = resolveCustomer();
    let type = null;
    for (const [re, tp] of APPT_TYPES) if (re.test(norm)) { type = tp; break; }
    if (!type) type = "kesif";
    custAmb(c, true);
    if (!dt.hasDate && !dt.hasTime) amb.push({ field: "date", kind: "missing" });
    else if (!dt.hasTime) amb.push({ field: "time", kind: "missing" });
    dtAmb();
    return result("appointment.create", { customer: customerOut(c), date: dt.date, time: dt.time, at: atOf(), type }, 0.92 - 0.06 * amb.filter((a) => !["ampm", "assumed", "vague", "same_weekday"].includes(a.kind)).length - 0.03 * amb.filter((a) => ["ampm", "assumed", "vague", "same_weekday"].includes(a.kind)).length, amb);
  }

  // ===== 12) MÜŞTERİ ARA =====
  const searchWords = /\b(ara|arayin|bul|bulun|bulsana|goster|getir|kim|kimdir|telefon\w*|numara\w*|tel|adres\w*|bilgi\w*|kayit\w*|ac|acin|musteri\w*)\b/;
  if (searchWords.test(norm) && !writeVerb) {
    const hits = hitsAll.filter((h) => h.score >= 0.6).sort((a, b) => b.score - a.score);
    const c = resolveCustomerSoft();
    let q = c ? c.query : null;
    if (!q) {
      // "müşteri ara ahmet" → geri kalan sözcükler
      q = remainder(tokens, used, (tk) => /^(musteri\w*|ara|arayin|bul|bulun|bulsana|goster|getir|kim|kimdir|telefonu|telefon|numarasi|numara|bilgileri|bilgisi|bilgi|adresi|adres|kayit\w*|ac|acin|tel|bir|lutfen|icin|ismi|adli|isimli|ismindeki|adindaki)$/.test(tk.t) || GLUE.has(tk.t) || SUFFIXES_ONLY.has(tk.t));
    }
    if (!q && !hits.length) amb.push({ field: "query", kind: "missing" });
    return result("customer.search", { query: q || null, customer: customerOut(c), matches: hits.slice(0, 8).map((h) => ({ key: h.cand.key, name: h.cand.name, phone: h.cand.phone || null, score: h.score })) }, q || hits.length ? 0.85 : 0.4, amb);
  }

  return result("unknown", {}, 0.1);

  // ---- yardımcılar (kapsam: parseCommand) ----
  function resolveCustomerSoft() {
    // sorgu/hatırlatmada müşteri isteğe bağlı: yalnız eşleşme varsa döner; tahmin (bulunamadı) yalnız honorific varsa
    if (hitsAll.length) return resolveCustomer();
    const g = guessQuery(tokens, used);
    if (g && g.idx.some((k) => HONORIFIC_RE.test(tokens[k].t))) { g.idx.forEach((k) => used.add(k)); return { query: g.query, matched: null, candidates: [], notFound: true }; }
    return null;
  }
}

const SUFFIXES_ONLY = new Set(["a", "e", "i", "u", "in", "un", "yi", "yu", "ye", "ya", "den", "dan", "de", "da", "ne", "na", "nin", "nun"]);

function numAtTok(tokens, i) {
  const t = tokens[i]?.t;
  if (!t) return null;
  if (/^\d{1,2}$/.test(t)) return { v: Number(t), len: 1 };
  const w = readWordNumber(tokens, i);
  if (w && w.value > 0 && w.value < 100) return { v: w.value, len: w.next - i };
  return null;
}

function dedupeHits(hits) {
  const best = new Map();
  for (const h of hits) { const k = h.cand.key; if (!best.has(k) || best.get(k).score < h.score) best.set(k, h); }
  return [...best.values()];
}

function cleanTitle(s) {
  s = String(s || "").replace(/\s+/g, " ").trim();
  s = s.replace(/^[,;:\-–\s]+|[,;:\-–\s]+$/g, "").replace(/\s+(ve|ile|icin)$/i, "");
  if (!s) return "";
  const f = s.charAt(0);
  return (f === "i" ? "İ" : f === "ı" ? "I" : f.toLocaleUpperCase("tr")) + s.slice(1);
}

function canonCategory(s) {
  const t = String(s || "").trim();
  if (!t) return "";
  const lc = t.toLocaleLowerCase("tr").replace(/ı/g, "i").replace(/ü/g, "u").replace(/ö/g, "o").replace(/ş/g, "s").replace(/ç/g, "c").replace(/ğ/g, "g");
  const map = [[/kira/, "Kira"], [/(benzin|mazot|akaryakit|yakit|lpg)/, "Yakıt"], [/malzeme/, "Malzeme"], [/(nakliye|tasima|kargo)/, "Nakliye"], [/(iscilik|yevmiye|usta|maas|iscis)/, "İşçilik"], [/(yemek|ogle yemegi|market)/, "Yemek"], [/(elektrik|dogalgaz|su faturasi|internet|telefon|fatura)/, "Fatura"], [/(vergi|sigorta|kdv)/, "Vergi/Sigorta"]];
  for (const [re, name] of map) if (re.test(lc)) return name;
  return t.split(/\s+/).slice(0, 3).map((w) => w.charAt(0).toLocaleUpperCase("tr") + w.slice(1)).join(" ");
}

/** Dönem çözümleme: bugün/yarın/bu hafta/bu ay/geçen ay/bu yıl/… → {period, from, to(hariç)} */
function resolvePeriod(tokens, norm, now, used, dt, opts = {}) {
  const amb = [];
  const today = todayOf(now);
  const p = istParts(now);
  const mk = (period, from, to) => ({ period, from, to, amb });
  if (/\bgecen ay\b/.test(norm)) { const f = addMonths(ymd(p.y, p.m, 1), -1); return mk("last_month", f, ymd(p.y, p.m, 1)); }
  if (/\bgecen hafta\b/.test(norm)) { const mon = addDays(today, -weekdayOf(today)); return mk("last_week", addDays(mon, -7), mon); }
  if (/\b(bu yil|bu sene|yil basindan|bu yilki)\b/.test(norm)) return mk("year", ymd(p.y, 1, 1), ymd(p.y + 1, 1, 1));
  if (/\bgecen (yil|sene)\b/.test(norm)) return mk("last_year", ymd(p.y - 1, 1, 1), ymd(p.y, 1, 1));
  if (/\bbu ay\b|\bayin\b.*\b(basindan|basindan beri)\b|\bbu aylik\b/.test(norm)) return mk("month", ymd(p.y, p.m, 1), addMonths(ymd(p.y, p.m, 1), 1));
  if (/\b(gelecek|onumuzdeki|sonraki) ay\b/.test(norm)) { const f = addMonths(ymd(p.y, p.m, 1), 1); return mk("next_month", f, addMonths(f, 1)); }
  if (/\b(bu hafta|haftalik|hafta icinde|bu haftaki)\b/.test(norm)) { const mon = addDays(today, -weekdayOf(today)); return mk("week", mon, addDays(mon, 7)); }
  if (/\b(gelecek|onumuzdeki|sonraki) hafta\b|\bhaftaya\b/.test(norm) && !tokens.some((x) => WD_RE.test(x.t))) { const mon = addDays(today, 7 - weekdayOf(today)); return mk("next_week", mon, addDays(mon, 7)); }
  // ay adı: "kasım ayı", "ekim"
  for (const tk of tokens) {
    const mm = /^(ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik)(da|de|ta|te|in|un)?$/.exec(tk.t);
    if (mm) { const mo = MONTHS[mm[1]]; const y = mo > p.m + 0 && false ? p.y - 1 : p.y; return mk("month_named", ymd(y, mo, 1), addMonths(ymd(y, mo, 1), 1)); }
  }
  if (dt.hasDate) {
    if (/\bgun\w*\b/.test(norm) || true) return { period: dt.date === today ? "today" : "day", from: dt.date, to: addDays(dt.date, 1), amb: [] };
  }
  if (/\bbugun\b|\bbu gun\b/.test(norm)) return mk("today", today, addDays(today, 1));
  const dp = opts.defaultPeriod || "month";
  if (dp === "today") return mk("today", today, addDays(today, 1));
  return mk("month", ymd(p.y, p.m, 1), addMonths(ymd(p.y, p.m, 1), 1));
}

module.exports = { parseCommand, resolvePeriod, canonCategory, MAX_TEXT };
