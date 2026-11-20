/**
 * Türkçe tarih/saat ayrıştırıcı (kural tabanlı). Saat dilimi: Europe/Istanbul (UTC+3, yaz saati yok).
 * Girdi: tokenize() jetonları + `now` (Date). Çıktı sabit yapı; tükettiği jeton indeksleri `used` kümesine eklenir.
 *
 * Desteklenen (örnekler): bugün, yarın, öbür gün, dün, 3 gün sonra, iki hafta sonra, 2 saat sonra, yarım saat sonra,
 * cuma / cuma günü / cumaya, haftaya salı, bu cuma, gelecek cuma, geçen cuma, 25 Kasım, 25 Kasım 2026, 25.11, 25.11.2026,
 * 2026-11-25, ayın 15'i, ay sonu, gelecek ay, haftaya, hafta sonu,
 * 10:30, saat 10, 10'da, on buçukta, öğleden sonra 3, akşam 6'da, sabah 9, gece 11, bu akşam, yarın sabah.
 */
const IST_OFFSET_MS = 3 * 3600 * 1000;
const pad = (n) => String(n).padStart(2, "0");

function istParts(date) {
  const t = new Date(date.getTime() + IST_OFFSET_MS);
  return { y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate(), h: t.getUTCHours(), mi: t.getUTCMinutes(), wd: (t.getUTCDay() + 6) % 7 };
}
const ymd = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;
function splitYmd(s) { const [y, m, d] = s.split("-").map(Number); return { y, m, d }; }
function addDays(s, n) { const { y, m, d } = splitYmd(s); const t = new Date(Date.UTC(y, m - 1, d + n)); return ymd(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate()); }
function weekdayOf(s) { const { y, m, d } = splitYmd(s); return (new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7; }
const daysInMonth = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
function validDate(y, m, d) { return m >= 1 && m <= 12 && d >= 1 && d <= daysInMonth(y, m); }
function addMonths(s, n) {
  const { y, m, d } = splitYmd(s);
  const t = (y * 12 + (m - 1)) + n; const ny = Math.floor(t / 12), nm = (t % 12) + 1;
  return ymd(ny, nm, Math.min(d, daysInMonth(ny, nm)));
}
const toISO = (date, time) => `${date}T${time || "00:00"}:00+03:00`;
const dateToEpoch = (date, time) => new Date(toISO(date, time)).getTime();
function todayOf(now) { const p = istParts(now); return ymd(p.y, p.m, p.d); }

const WEEKDAYS = { pazartesi: 0, sali: 1, carsamba: 2, persembe: 3, cuma: 4, cumartesi: 5, pazar: 6 };
const WD_RE = /^(pazartesi|sali|carsamba|persembe|cumartesi|cuma|pazar)(ya|ye|a|e|na|ne|nin|nun|si|ki|dan|den|da|de|ta|te|yi|i|u|nu|lari|leri|gunu|gunune)?$/;
const MONTHS = { ocak: 1, subat: 2, mart: 3, nisan: 4, mayis: 5, haziran: 6, temmuz: 7, agustos: 8, eylul: 9, ekim: 10, kasim: 11, aralik: 12 };
const MONTH_RE = /^(ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik)(da|de|ta|te|dan|den|a|e|in|un|i|u|ya|ye|ayi)?$/;
const SUFFIX = new Set(["da", "de", "ta", "te", "dan", "den", "tan", "ten", "a", "e", "ya", "ye", "na", "ne", "i", "u", "yi", "yu", "in", "un", "nin", "nun", "si", "su", "ine", "ina", "inde", "inda", "sine", "sina", "ki", "gunu", "gun", "gunune"]);
const WORD_HOURS = { bir: 1, iki: 2, uc: 3, dort: 4, bes: 5, alti: 6, yedi: 7, sekiz: 8, dokuz: 9, on: 10, "on bir": 11, "on iki": 12 };
const LOC = new Set(["da", "de", "ta", "te"]);
const NUMW = { bir: 1, iki: 2, uc: 3, dort: 4, bes: 5, alti: 6, yedi: 7, sekiz: 8, dokuz: 9, on: 10, yirmi: 20, otuz: 30 };

function numAt(tokens, i) {
  if (!tokens[i]) return null;
  const t = tokens[i].t;
  if (/^\d{1,3}$/.test(t)) return { v: Number(t), len: 1 };
  if (t in NUMW) {
    if (t === "on" || t === "yirmi" || t === "otuz") {
      const nx = tokens[i + 1] && tokens[i + 1].t;
      if (nx in NUMW && NUMW[nx] < 10 && NUMW[t] >= 10) return { v: NUMW[t] + NUMW[nx], len: 2 };
    }
    return { v: NUMW[t], len: 1 };
  }
  // bitişik: "onbir", "yirmibes" (nadir) — desteklenmez
  return null;
}

/**
 * @returns {{date:string|null, time:string|null, approxTime:boolean, hasDate:boolean, hasTime:boolean, offsetMinutes:number|null,
 *            ambiguities:object[], vague:boolean, relativePast:boolean, endOfMonth:boolean}}
 */
function parseDateTime(tokens, used, now, opts = {}) {
  const today = todayOf(now);
  const todayWd = weekdayOf(today);
  const out = { date: null, time: null, approxTime: false, hasDate: false, hasTime: false, offsetMinutes: null, ambiguities: [], vague: false, relativePast: false, endOfMonth: false, span: null };
  const use = (a, b) => { for (let k = a; k < b; k++) used.add(k); };
  const free = (i) => tokens[i] && !used.has(i);
  const t = (i) => (tokens[i] ? tokens[i].t : "");
  const eatSuffix = (i) => { let j = i; while (free(j) && SUFFIX.has(t(j)) && j - i < 2) j++; return j; };
  const setDate = (d, vague = false) => { if (!out.hasDate) { out.date = d; out.hasDate = true; if (vague) out.vague = true; } };
  const prevTok = (i, back = 1) => (i - back >= 0 && !used.has(i - back) ? t(i - back) : "");

  // ---- 0) göreli süre: "2 saat sonra", "yarım saat sonra", "45 dakika sonra"
  for (let i = 0; i < tokens.length; i++) {
    if (used.has(i)) continue;
    let n = null, len = 0, half = false;
    if (t(i) === "yarim" && /^(saat)$/.test(t(i + 1)) && /^sonra/.test(t(i + 2))) { n = 30; len = 1; half = true; }
    else {
      const nn = numAt(tokens, i);
      if (nn && /^(saat|dakika|dk)$/.test(t(i + nn.len)) && /^sonra/.test(t(i + nn.len + 1))) {
        n = t(i + nn.len) === "saat" ? nn.v * 60 : nn.v; len = nn.len;
        // "bir buçuk saat sonra"
      }
    }
    if (n !== null) {
      const end = half ? i + 3 : i + len + 2;
      const nxt = tokens[end] && /^(sonra|sonrasi|sonraya|sonrasina)$/.test(t(end - 1)) ? end : end;
      use(i, Math.min(end, tokens.length));
      out.offsetMinutes = n; out.hasTime = true; out.hasDate = true;
      const at = new Date(now.getTime() + n * 60000);
      const p = istParts(at);
      out.date = ymd(p.y, p.m, p.d); out.time = `${pad(p.h)}:${pad(p.mi)}`;
      return finish();
    }
  }

  // ---- 1) TARİH
  for (let i = 0; i < tokens.length && !out.hasDate; i++) {
    if (used.has(i)) continue;
    const s = t(i);
    // ISO
    let m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
    if (m && validDate(+m[1], +m[2], +m[3])) { setDate(ymd(+m[1], +m[2], +m[3])); use(i, i + 1); break; }
    // 25.11.2026 / 25/11/2026 / 25.11 / 25/11
    m = /^(\d{1,2})([./])(\d{1,2})(?:[./](\d{2,4}))?$/.exec(s);
    if (m) {
      const d = +m[1], mo = +m[3];
      const hasYear = m[4] !== undefined;
      const timeLike = m[2] === "." && !hasYear && (prevTok(i) === "saat" || (LOC.has(t(i + 1)) && mo >= 13) || mo >= 13 || t(i + 1) === "gibi");
      if (!timeLike && validDate(2000, mo, d)) {
        let y;
        if (hasYear) { y = +m[4]; if (y < 100) y += 2000; }
        else { y = istParts(now).y; if (ymd(y, mo, d) < today) y += 1; }
        if (validDate(y, mo, d)) { setDate(ymd(y, mo, d)); use(i, eatSuffixIdx(i + 1)); break; }
      }
    }
    // "25 kasım [2026]"
    const nn = numAt(tokens, i);
    if (nn && nn.v >= 1 && nn.v <= 31 && MONTH_RE.test(t(i + nn.len))) {
      const mm = MONTH_RE.exec(t(i + nn.len));
      const mo = MONTHS[mm[1]];
      let j = i + nn.len + 1, y = null;
      if (free(j) && /^\d{4}$/.test(t(j)) && +t(j) >= 2000 && +t(j) <= 2100) { y = +t(j); j++; }
      j = eatSuffixIdx(j);
      if (y === null) { y = istParts(now).y; if (ymd(y, mo, nn.v) < today) y += 1; }
      if (validDate(y, mo, nn.v)) { setDate(ymd(y, mo, nn.v)); use(i, j); break; }
    }
    // "kasımın 25'i", "kasım 25"
    m = MONTH_RE.exec(s);
    if (m && /^(in|un|ayi|)$/.test(m[2] || "") ) {
      let j = i + 1;
      if (free(j) && /^(in|un)$/.test(t(j))) j++;
      const dn = numAt(tokens, j);
      if (dn && dn.v >= 1 && dn.v <= 31) {
        const mo = MONTHS[m[1]]; let y = istParts(now).y;
        if (ymd(y, mo, dn.v) < today) y += 1;
        if (validDate(y, mo, dn.v)) { setDate(ymd(y, mo, dn.v)); use(i, eatSuffixIdx(j + dn.len)); break; }
      }
    }
    // göreli günler
    if (/^bugun(un|e|ku|de|den)?$/.test(s) || (s === "bu" && /^gun(e|ku|de)?$/.test(t(i + 1)))) { setDate(today); use(i, s === "bu" ? i + 2 : i + 1); break; }
    if (/^yarin(a|ki|da|dan|i)?$/.test(s)) { setDate(addDays(today, 1)); use(i, i + 1); break; }
    if ((s === "obur" || s === "ertesi") && /^gun/.test(t(i + 1))) { setDate(addDays(today, s === "obur" ? 2 : 1)); use(i, i + 2); break; }
    if (/^(oburgun|ertesigun)(e|u)?$/.test(s)) { setDate(addDays(today, s.startsWith("obur") ? 2 : 1)); use(i, i + 1); break; }
    if (/^dun(ku|e)?$/.test(s)) { setDate(addDays(today, -1)); out.relativePast = true; use(i, i + 1); break; }
    if (/^(evvelsi|onceki)$/.test(s) && /^gun/.test(t(i + 1))) { setDate(addDays(today, -2)); out.relativePast = true; use(i, i + 2); break; }
    // "N gün/hafta/ay sonra"
    const rn = numAt(tokens, i);
    if (rn && /^(gun|hafta|ay)(a|e|i)?$/.test(t(i + rn.len)) && /^sonra/.test(t(i + rn.len + 1))) {
      const unit = t(i + rn.len).replace(/(a|e|i)$/, "");
      const d = unit === "gun" ? addDays(today, rn.v) : unit === "hafta" ? addDays(today, rn.v * 7) : addMonths(today, rn.v);
      setDate(d); use(i, i + rn.len + 2); break;
    }
    if (rn && /^(gun|hafta|ay)$/.test(t(i + rn.len)) && /^(icinde|icerisinde)$/.test(t(i + rn.len + 1))) { /* "3 gün içinde": belirsiz → yok say */ }
    // "haftaya" tek başına / "bir sonraki hafta"
    if (s === "haftaya" && !(WD_RE.test(t(i + 1)))) { setDate(addDays(today, 7)); use(i, i + 1); break; }
    if (/^(gelecek|onumuzdeki|sonraki)$/.test(s) && t(i + 1) === "hafta" && !WD_RE.test(t(i + 2))) { setDate(addDays(today, 7)); use(i, i + 2); break; }
    // "hafta sonu"
    if (s === "hafta" && /^sonu/.test(t(i + 1))) { const d = ((5 - todayWd + 7) % 7) || 7; setDate(addDays(today, d)); out.vague = true; use(i, i + 2); break; }
    // ay sonu / ay başı / ayın 15'i / gelecek ay [N]
    if (s === "ay" && /^(sonu|sonunda|sonuna|sonundan)$/.test(t(i + 1))) { const { y, m: mo } = istParts(now); setDate(ymd(y, mo, daysInMonth(y, mo))); out.endOfMonth = true; use(i, i + 2); break; }
    if (/^ayin$/.test(s) || (s === "ay" && /^(in)$/.test(t(i + 1)))) {
      let j = i + (s === "ay" ? 2 : 1);
      if (/^(sonu|sonunda|sonuna|sonundan)$/.test(t(j))) { const { y, m: mo } = istParts(now); setDate(ymd(y, mo, daysInMonth(y, mo))); out.endOfMonth = true; use(i, j + 1); break; }
      if (/^(basi|basinda)$/.test(t(j))) { setDate(addMonths(today.slice(0, 8) + "01", 1)); use(i, j + 1); break; }
      const dn = numAt(tokens, j);
      if (dn && dn.v >= 1 && dn.v <= 31) {
        const p = istParts(now); let y = p.y, mo = p.m;
        if (ymd(y, mo, Math.min(dn.v, daysInMonth(y, mo))) < today) { mo += 1; if (mo > 12) { mo = 1; y++; } }
        if (validDate(y, mo, dn.v)) { setDate(ymd(y, mo, dn.v)); use(i, eatSuffixIdx(j + dn.len)); break; }
      }
    }
    if (s === "ay" && /^basi/.test(t(i + 1))) { setDate(addMonths(today.slice(0, 8) + "01", 1)); use(i, i + 2); break; }
    if (/^(gelecek|onumuzdeki|sonraki)$/.test(s) && /^ay(a|in|da)?$/.test(t(i + 1))) {
      let j = i + 2;
      if (free(j) && /^(in)$/.test(t(j))) j++;
      const dn = numAt(tokens, j);
      if (dn && dn.v >= 1 && dn.v <= 31) {
        const nm = addMonths(today.slice(0, 8) + "01", 1); const { y, m: mo } = splitYmd(nm);
        if (validDate(y, mo, dn.v)) { setDate(ymd(y, mo, dn.v)); use(i, eatSuffixIdx(j + dn.len)); break; }
      }
      setDate(addMonths(today, 1), true); use(i, i + 2); break;
    }
    // hafta günleri (+ değiştiriciler)
    const wm = WD_RE.exec(s);
    if (wm && (wm[2] === undefined || true)) {
      // "pazar" + "yeri"? / "Cuma" özel ad riskini çağıran (entities) çözer; burada tarih sayılır
      const wd = WEEKDAYS[wm[1]];
      let from = i, mode = "next";
      const p1 = prevTok(i, 1), p2 = prevTok(i, 2);
      if (p1 === "haftaya") { mode = "nextweek"; from = i - 1; }
      else if (/^(gelecek|onumuzdeki|sonraki)$/.test(p2) && p1 === "hafta") { mode = "nextweek"; from = i - 2; }
      else if (p2 === "bu" && p1 === "hafta") { mode = "thisweek"; from = i - 2; }
      else if (/^(gelecek|onumuzdeki|sonraki)$/.test(p1)) { mode = "next"; from = i - 1; }
      else if (p1 === "bu") { mode = "thisweek"; from = i - 1; }
      else if (/^gecen$/.test(p1)) { mode = "past"; from = i - 1; }
      else if (p2 === "gecen" && p1 === "hafta") { mode = "pastweek"; from = i - 2; }
      let delta;
      if (mode === "next") delta = ((wd - todayWd + 7) % 7) || 7;
      else if (mode === "thisweek") { delta = wd - todayWd; if (delta < 0) delta += 7; }
      else if (mode === "nextweek") delta = (7 - todayWd) + wd;
      else if (mode === "past") { delta = -(((todayWd - wd + 7) % 7) || 7); out.relativePast = true; }
      else { delta = -(todayWd + 7 - wd); out.relativePast = true; }
      const date = addDays(today, delta);
      setDate(date);
      if (mode === "next" && wd === todayWd && p1 === "") out.ambiguities.push({ field: "date", kind: "same_weekday", options: [today, date] });
      let j = i + 1;
      if (free(j) && /^(gunu|gun|gunune|gunku|gunleri)$/.test(t(j))) j++;
      j = eatSuffixIdx(j);
      use(from, j); out.span = [from, j];
      break;
    }
  }

  // ---- 2) SAAT / gün periyodu
  const periodAt = (i) => {
    const s = t(i);
    if (s === "sabah" || s === "sabahleyin" || s === "sabahtan") return { p: "sabah", len: 1 };
    if (s === "ogleden" && t(i + 1) === "sonra") return { p: "ogledensonra", len: 2 };
    if (s === "ogleden" && t(i + 1) === "once") return { p: "ogledenonce", len: 2 };
    if (s === "oglen" || s === "ogle" || s === "ogleyin" || s === "ogleye") return { p: "oglen", len: 1 };
    if (s === "aksam" || s === "aksamleyin" || s === "aksama") return { p: "aksam", len: 1 };
    if (s === "aksamustu" || s === "aksamustune") return { p: "aksam", len: 1 };
    if (s === "gece" || s === "geceleyin" || s === "geceye") return { p: "gece", len: 1 };
    return null;
  };
  const adj = (h, p) => {
    if (p === "sabah" || p === "ogledenonce") return h === 12 ? 12 : h;
    if (p === "oglen") return h >= 1 && h <= 5 ? h + 12 : h;
    if (p === "ogledensonra" || p === "aksam") return h < 12 ? h + 12 : h;
    if (p === "gece") return h === 12 ? 0 : h >= 6 && h < 12 ? h + 12 : h;
    return h;
  };
  const PERIOD_DEFAULT = { sabah: "09:00", oglen: "12:00", ogledensonra: "14:00", ogledenonce: "11:00", aksam: "18:00", gece: "21:00" };

  // "bu akşam / bu sabah / bu gece" → bugün + periyot
  for (let i = 0; i < tokens.length - 1; i++) {
    if (used.has(i) || used.has(i + 1)) continue;
    if (t(i) === "bu") { const pp = periodAt(i + 1); if (pp && (pp.p === "aksam" || pp.p === "sabah" || pp.p === "gece")) { if (!out.hasDate) setDate(today); use(i, i + 1); break; } }
  }

  let found = false;
  for (let i = 0; i < tokens.length && !found; i++) {
    if (used.has(i)) continue;
    const pp = periodAt(i);
    // (periyot) (saat)
    if (pp) {
      let j = i + pp.len;
      const tm = readClock(j, true);
      if (tm) { setTime(adj(tm.h, pp.p), tm.m); use(i, tm.next); found = true; break; }
    }
    // (saat) (periyot)  örn. "9 sabah", "3 ogleden sonra"
    const tm0 = readClock(i, false);
    if (tm0) {
      const p2 = periodAt(tm0.next);
      if (p2 && tm0.explicitPeriodOk) { setTime(adj(tm0.h, p2.p), tm0.m); use(i, tm0.next + p2.len); found = true; break; }
      // saat ifadesi doğrudan (a) 24 saat/iki nokta, (b) "saat" öneki, (c) ek (de/da) var
      if (tm0.sure) {
        let h = tm0.h;
        if (tm0.bare) { // "3'te" → mesai varsayımı + belirsizlik
          if (h >= 1 && h <= 6) { out.ambiguities.push({ field: "time", kind: "ampm", options: [`${pad(h)}:${pad(tm0.m)}`, `${pad(h + 12)}:${pad(tm0.m)}`] }); h += 12; }
        }
        setTime(h, tm0.m); use(i, tm0.next); found = true; break;
      }
    }
  }
  // periyot tek başına
  if (!found) {
    for (let i = 0; i < tokens.length; i++) {
      if (used.has(i)) continue;
      const pp = periodAt(i);
      if (pp && !/^(ogledenonce)$/.test(pp.p)) {
        if (pp.p === "gece" && !out.hasDate && false) continue;
        out.time = PERIOD_DEFAULT[pp.p]; out.hasTime = true; out.approxTime = true;
        use(i, i + pp.len);
        break;
      }
    }
  }

  return finish();

  function eatSuffixIdx(i) { return eatSuffix(i); }
  function setTime(h, m) {
    if (out.hasTime) return;
    if (h === 24) h = 0;
    out.time = `${pad(h)}:${pad(m)}`; out.hasTime = true;
  }
  /**
   * i. jetondan bir saat okur. Dönüş {h,m,next,sure,bare,explicitPeriodOk}
   *  - "10:30", "10.30"
   *  - "saat 10", "saat 10 buçuk", "saat on bir"
   *  - "10 da/de/ta/te", "10 gibi", "10 sularinda", "10 civari", (isteğe bağlı) "11 e/a" (opts.dativeTime)
   *  - "on buçuk(ta)", "dokuzda"
   * inPeriod=true iken (periyoddan sonra) çıplak sayı da kabul edilir ("öğleden sonra 3").
   */
  function readClock(i, inPeriod) {
    if (!free(i)) return null;
    let j = i, saat = false;
    if (t(j) === "saat") { saat = true; j++; if (!free(j)) return null; }
    const s = t(j);
    let m = /^(\d{1,2})[:.](\d{2})$/.exec(s);
    if (m && +m[1] <= 24 && +m[2] < 60) {
      if (m[0].includes(".") && !saat && !inPeriod && !LOC.has(t(j + 1)) && !/^(gibi|sularinda|civari|de|da)$/.test(t(j + 1))) {
        if (+m[1] > 23) return null;
      }
      const next = skipClockSuffix(j + 1);
      return { h: +m[1], m: +m[2], next, sure: true, bare: false, explicitPeriodOk: true };
    }
    // sayı (rakam veya sözcük)
    const n = numAt(tokens, j);
    if (n && n.v >= 0 && n.v <= 24 && !(t(j) !== "" && /^\d{3,}$/.test(t(j)))) {
      let k = j + n.len, mins = 0, hadBucuk = false, hadSuffix = false;
      if (t(k) === "bucuk" || /^bucuk(ta|te|a|e|u)$/.test(t(k))) { mins = 30; k++; hadBucuk = true; if (free(k) && LOC.has(t(k))) { k++; hadSuffix = true; } }
      else if (t(k) === "bucuga" || t(k) === "bucugu") { mins = 30; k++; hadBucuk = true; }
      else if (t(k) === "ceyrek" ) { /* "on çeyrek var": desteklenmez */ }
      if (hadBucuk && !saat && !hadSuffix && !inPeriod) return null;
      if (hadBucuk && /^(bin|milyon|tl|lira)$/.test(t(k))) return null;
      if (!hadBucuk) {
        if (free(k) && (LOC.has(t(k)))) { hadSuffix = true; k++; }
        else if (free(k) && /^(gibi|sularinda|sularinda|civarinda|civari|itibariyle)$/.test(t(k))) { hadSuffix = true; k++; }
        else if (opts.dativeTime && free(k) && /^(e|a|ye|ya)$/.test(t(k))) { hadSuffix = true; k++; }
      }
      // "N gün/hafta/saat/ay/bin/TL..." sayıdan sonra gelen birim ise saat değildir
      if (!saat && /^(gun|hafta|ay|saat|dakika|dk|bin|milyon|tl|lira|kisi|adet|metre|m|cm|kasa)$/.test(t(k)) && !hadBucuk) return null;
      if (saat || hadSuffix || hadBucuk || inPeriod) {
        const tight = saat || hadSuffix || hadBucuk;
        return { h: n.v, m: mins, next: k, sure: true, bare: !(n.v >= 13 || n.v === 0 || inPeriod), explicitPeriodOk: true, tight };
      }
      // çıplak sayı + sonrasında periyot: "9 sabah"
      if (periodAt(k)) return { h: n.v, m: 0, next: k, sure: false, bare: false, explicitPeriodOk: true };
    }
    // bitişik sözcük saat: "dokuzda", "onda", "ikide"
    const wm = /^(bir|iki|uc|dort|bes|alti|yedi|sekiz|dokuz|on)(da|de|ta|te)$/.exec(s);
    if (wm) return { h: WORD_HOURS[wm[1]], m: 0, next: j + 1, sure: true, bare: true, explicitPeriodOk: true };
    return null;
  }
  function skipClockSuffix(k) {
    if (free(k) && /^(da|de|ta|te|gibi|sularinda|civari|civarinda)$/.test(t(k))) return k + 1;
    return k;
  }
  function finish() {
    // yalnız saat varsa (tarih yok): saat geçmediyse bugün, geçtiyse yarın — varsayım olarak işaretle
    if (out.hasTime && !out.hasDate && opts.assumeDateFromTime !== false) {
      const p = istParts(now);
      const nowMin = p.h * 60 + p.mi;
      const [hh, mm] = out.time.split(":").map(Number);
      if (hh * 60 + mm > nowMin) out.date = today; else out.date = addDays(today, 1);
      out.assumedDate = true;
      out.ambiguities.push({ field: "date", kind: "assumed", options: [today, addDays(today, 1)] });
    }
    return out;
  }
}

module.exports = { parseDateTime, istParts, ymd, addDays, addMonths, weekdayOf, todayOf, toISO, dateToEpoch, daysInMonth, splitYmd, WEEKDAYS, MONTHS, pad, IST_OFFSET_MS, WD_RE, MONTH_RE };
