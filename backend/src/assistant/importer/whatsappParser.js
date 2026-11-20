/**
 * WhatsApp "Sohbeti dışa aktar" (.txt) ayrıştırıcısı — çok kalıplı, kural tabanlı; dışarıya hiçbir şey göndermez.
 *
 * Desteklenen biçimler (yerel ayara göre değişen):
 *   Android : `20.11.2026 14:05 - Ahmet Bey: mesaj`, `20/11/2026, 14:05 - …`, `11/20/26, 2:05 PM - …`, `20.11.2026 02:05 ÖS - …`
 *   iOS     : `[20.11.2026 14:05:12] Ahmet Bey: mesaj`, `[20.11.26, 14:05:12] …`, `[11/20/26, 2:05:12 PM] …`
 *   Tarih   : gg.aa.yyyy | gg/aa/yy | aa/gg/yy (kanıta göre) | yyyy-aa-gg ; Saat: 24 sa. veya 12 sa. (AM/PM, ÖÖ/ÖS)
 *   Satırlar: çok satırlı mesajlar, sistem mesajları (şifreleme, katıldı/ayrıldı…), medya satırları, silinen mesaj, konum.
 *   Unicode yön/görünmez işaretleri (LRM/RLM/BOM/NNBSP…) temizlenir.
 * Saat dilimi: dışa aktarma telefonun yerel saatindedir → Europe/Istanbul (UTC+3) kabul edilir.
 */
const INVISIBLE_RE = /[​-‏‪-‮⁠-⁩﻿­]/g;
const SPACE_RE = /[    　]/g;

const DATE_PART = "(\\d{1,4}[./-]\\d{1,2}[./-]\\d{1,4})";
const TIME_PART = "(\\d{1,2}[:.]\\d{2}(?::\\d{2})?)";
const AMPM = "([AaPp]\\.?\\s?[Mm]\\.?|ÖÖ|ÖS|öö|ös|Ö\\.Ö\\.|Ö\\.S\\.)";
const ANDROID_RE = new RegExp(`^${DATE_PART},?\\s+${TIME_PART}\\s*${AMPM}?\\s+[-–—]\\s+(.*)$`);
const IOS_RE = new RegExp(`^\\[${DATE_PART},?\\s+${TIME_PART}\\s*${AMPM}?\\]\\s*(.*)$`);

const SYSTEM_RES = [
  /u[cç]tan uca [sş]ifrelidir|end-to-end encrypted|uçtan uca şifrel/i,
  /g[üu]venlik kodu(nuz)? de[gğ]i[sş]ti|security code (with .+ )?changed/i,
  /\b(kat[ıi]ld[ıi]|ayr[ıi]ld[ıi]|joined|left)\s*$/i,
  /(grubu|toplulu[gğ]u)\s+olu[sş]turdu|created (group|this group)/i,
  /\b(ekledi|ç[ıi]kard[ıi]|added|removed)\b.*$/i,
  /numaras[ıi]n[ıi] de[gğ]i[sş]tirdi|changed (their|his|her) phone number/i,
  /grup (ad[ıi]n[ıi]|a[cç][ıi]klamas[ıi]n[ıi]|simgesini|ayarlar[ıi]n[ıi]) de[gğ]i[sş]tir|changed the (group|subject|description|icon)/i,
  /cevaps[ıi]z (sesli|g[öo]r[üu]nt[üu]l[üu]) arama|missed (voice|video) call/i,
  /bu sohbet.*(i[cç]in )?(mesaj|s[üu]reli)|disappearing messages/i,
  /mesajlar ge[cç]ici|messages (are now )?disappear/i,
];
const MEDIA_RES = [
  /^<?\s*(medya|media)\s+(dahil edilmedi|omitted)\s*>?$/i,
  /^<\s*attached:[^>]*>$/i,
  /^<\s*(eklenti|ek):[^>]*>$/i,
  /^(g[öo]r[üu]nt[üu]|resim|foto[gğ]raf|video|ses|ses mesaj[ıi]|belge|dosya|sticker|çıkartma|gif|ki[sş]i kart[ıi]|image|audio|voice message|document|contact card)\s+(dahil edilmedi|omitted)$/i,
  /^.{1,150}\.(jpe?g|png|webp|gif|heic|opus|ogg|mp4|mov|3gp|mp3|m4a|aac|pdf|docx?|xlsx?|pptx?|vcf|zip|txt)\s*\((dosya ekli|file attached)\)$/i,
  /^(dosya ekli|file attached)$/i,
];
const DELETED_RES = [/^bu mesaj silindi\.?$/i, /^mesaj[ıi] sildiniz\.?$/i, /^this message was deleted\.?$/i, /^you deleted this message\.?$/i, /^bu mesaj[ıi]?\s+sildiniz\.?$/i];
const LOCATION_RE = /^(konum|location)\s*:\s*https?:\/\/\S+/i;

function strip(s) { return s.replace(INVISIBLE_RE, "").replace(SPACE_RE, " "); }

/** "WhatsApp Chat with X.txt" / "WhatsApp Sohbeti - X.zip" / "WhatsApp ile X sohbeti" → X (ya da null) */
function titleFromFileName(name) {
  if (!name) return null;
  let base = String(name).replace(/\\/g, "/").split("/").pop().replace(/\.(txt|zip)$/i, "");
  base = strip(base).trim();
  const pats = [
    /^WhatsApp Chat with (.+)$/i,
    /^WhatsApp Chat - (.+)$/i,
    /^WhatsApp Sohbeti - (.+)$/i,
    /^WhatsApp Sohbeti: (.+)$/i,
    /^WhatsApp ile (.+?) sohbeti$/i,
    /^(.+?) ile WhatsApp sohbeti$/i,
    /^Chat de WhatsApp con (.+)$/i,
  ];
  for (const re of pats) { const m = re.exec(base); if (m) return m[1].trim().slice(0, 120) || null; }
  if (/^_?chat$/i.test(base)) return null;
  return null;
}

/** Ham metin → satırlar; ilk geçişte başlık kalıpları ve tarih sırası kanıtı toplanır */
function parseWhatsAppText(input, opts = {}) {
  const maxMessages = opts.maxMessages || 50000;
  const maxTextLen = opts.maxTextLen || 8000;
  let text = String(input);
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const lines = text.split(/\r\n|\n|\r/);

  // ---- 1. geçiş: başlık satırlarını bul + tarih sırası kanıtı
  const heads = new Array(lines.length).fill(null);
  let styleCounts = { android: 0, ios: 0 };
  let evDay = 0, evMonth = 0, sepSlash = 0, sepDot = 0, hasAmPm = false, hasTrAmPm = false, ymdFirst = 0, dmyCount = 0;
  for (let i = 0; i < lines.length; i++) {
    const ln = strip(lines[i]);
    if (ln.length < 8 || ln.length > 20000) continue;
    let m = ANDROID_RE.exec(ln), style = "android";
    if (!m) { m = IOS_RE.exec(ln); style = "ios"; }
    if (!m) continue;
    const dp = m[1].split(/[./-]/);
    const sep = /[./-]/.exec(m[1])[0];
    heads[i] = { style, dateStr: m[1], timeStr: m[2], ampm: m[3] || null, rest: m[4], parts: dp, sep };
    styleCounts[style]++;
    if (dp[0].length === 4) ymdFirst++;
    else {
      dmyCount++;
      if (Number(dp[0]) > 12) evDay++;
      if (Number(dp[1]) > 12) evMonth++;
    }
    if (sep === "/") sepSlash++; else if (sep === ".") sepDot++;
    if (m[3]) { hasAmPm = true; if (/ö/i.test(m[3])) hasTrAmPm = true; }
  }
  const warnings = [];
  let order = "dmy";
  if (ymdFirst > dmyCount) order = "ymd";
  else if (evDay && !evMonth) order = "dmy";
  else if (evMonth && !evDay) order = "mdy";
  else if (evDay && evMonth) { order = "dmy"; warnings.push("date_order_mixed"); }
  else if (sepSlash > sepDot && hasAmPm && !hasTrAmPm) order = "mdy";
  const platform = styleCounts.ios > styleCounts.android ? "ios" : styleCounts.android ? "android" : "unknown";
  const locale = hasTrAmPm ? "tr" : hasAmPm ? "en" : "";

  // ---- 2. geçiş: mesajları kur
  const messages = [];
  let cur = null;
  let systemCount = 0, skippedBeforeFirst = 0;
  const pushCur = () => { if (cur) { finalize(cur); if (cur.kind === "system") systemCount++; else messages.push(cur); cur = null; } };
  for (let i = 0; i < lines.length; i++) {
    const h = heads[i];
    if (!h) {
      if (cur) cur.lines.push(strip(lines[i]));
      else if (lines[i].trim()) skippedBeforeFirst++;
      continue;
    }
    pushCur();
    if (messages.length >= maxMessages) { warnings.push("message_limit"); cur = null; break; }
    const ts = toTimestamp(h, order);
    if (!ts) { // geçersiz tarih (ör. 31.02) → önceki mesajın devamı say
      if (cur) cur.lines.push(strip(lines[i])); continue;
    }
    const { sender, body, hasSender } = splitSender(h.rest);
    cur = { ts: ts.date, localIso: ts.localIso, sender: hasSender ? sender : null, lines: [body], hasSender };
  }
  pushCur();
  if (messages.length >= maxMessages && !warnings.includes("message_limit")) { /* tam sınırda */ }

  // ---- tekilleştirme için sıra numarası (aynı dakika+gönderen+tür+metin tekrarları)
  const seen = new Map();
  for (const m of messages) {
    const k = `${m.localIso.slice(0, 16)}|${normSender(m.sender)}|${m.kind}|${m.text || ""}`;
    const n = (seen.get(k) || 0) + 1;
    seen.set(k, n);
    m.dedupeKey = k; m.n = n;
  }

  const participants = new Map();
  for (const m of messages) {
    if (!m.sender) continue;
    const p = participants.get(m.sender) || { name: m.sender, count: 0, isPhone: /^\+?[\d\s()-]{7,}$/.test(m.sender) };
    p.count++; participants.set(m.sender, p);
  }
  const stats = {
    platform, locale, date_order: order, time_format: hasAmPm ? "12h" : "24h",
    total_lines: lines.length, messages: messages.length, system: systemCount,
    text: messages.filter((m) => m.kind === "text").length,
    media: messages.filter((m) => m.kind === "media").length,
    deleted: messages.filter((m) => m.kind === "deleted").length,
    location: messages.filter((m) => m.kind === "location").length,
    first_at: messages.length ? messages[0].ts.toISOString() : null,
    last_at: messages.length ? messages[messages.length - 1].ts.toISOString() : null,
    participants: [...participants.values()].sort((a, b) => b.count - a.count),
    ignored_leading_lines: skippedBeforeFirst,
  };
  stats.is_group = stats.participants.length > 2;
  return { messages, stats, warnings };

  function finalize(c) {
    let body = c.lines.join("\n").replace(/\s+$/g, "");
    if (!c.hasSender) { c.kind = "system"; c.text = body; return; }
    if (body.length > maxTextLen) { body = body.slice(0, maxTextLen); c.truncated = true; }
    c.text = body;
    const one = body.trim();
    if (SYSTEM_RES.some((re) => re.test(one)) && /(uçtan uca|end-to-end|güvenlik kodu|security code)/i.test(one)) { c.kind = "system"; return; }
    if (MEDIA_RES.some((re) => re.test(one))) { c.kind = "media"; c.text = null; return; }
    if (DELETED_RES.some((re) => re.test(one))) { c.kind = "deleted"; c.text = null; return; }
    if (LOCATION_RE.test(one)) { c.kind = "location"; c.text = one.slice(0, 500); return; }
    // medya satırı + altyazı (iOS: "<attached: x.jpg>\nAltyazı") → metin olarak tut, medya etiketini at
    c.text = body.replace(/^\s*<\s*attached:[^>]*>\s*\n?/i, "").trim();
    if (!c.text) { c.kind = "media"; c.text = null; return; }
    c.kind = "text";
    delete c.lines;
  }
}

function splitSender(rest) {
  const r = rest.replace(/^\s+/, "");
  // Sistem iletileri: "Ahmet Bey katıldı", "Mesajlar ve aramalar..." — ": " yok
  const idx = r.indexOf(": ");
  if (idx <= 0 || idx > 120) return { sender: null, body: r, hasSender: false };
  const sender = r.slice(0, idx).trim();
  // Gönderen kısmında anlamsız uzunluk/yeni satır/URL varsa sistem satırı say
  if (!sender || /https?:\/\//i.test(sender)) return { sender: null, body: r, hasSender: false };
  return { sender, body: r.slice(idx + 2), hasSender: true };
}

const normSender = (s) => String(s || "").toLowerCase().replace(/\s+/g, " ").trim();

function toTimestamp(h, order) {
  const p = h.parts.map(Number);
  let y, mo, d;
  if (h.parts[0].length === 4) { [y, mo, d] = p; }
  else if (order === "mdy") { [mo, d, y] = p; }
  else { [d, mo, y] = p; }
  if (y < 100) y += 2000;
  if (!(y >= 2000 && y <= 2100) || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  const tm = h.timeStr.split(/[:.]/).map(Number);
  let hh = tm[0], mi = tm[1], ss = tm[2] || 0;
  if (h.ampm) {
    const pm = /^(p|ös|Ö\.S)/i.test(h.ampm.replace(/\s/g, ""));
    if (hh < 1 || hh > 12) return null;
    hh = (hh % 12) + (pm ? 12 : 0);
  }
  if (hh > 23 || mi > 59 || ss > 59) return null;
  const dim = new Date(Date.UTC(y, mo, 0)).getUTCDate();
  if (d > dim) return null;
  const pad = (n) => String(n).padStart(2, "0");
  const localIso = `${y}-${pad(mo)}-${pad(d)}T${pad(hh)}:${pad(mi)}:${pad(ss)}`;
  return { date: new Date(`${localIso}+03:00`), localIso };
}

module.exports = { parseWhatsAppText, titleFromFileName, strip, normSender };
