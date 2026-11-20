/** Türkçe biçimleme yardımcıları (kart özetleri ve okuma cevapları KOD tarafından üretilir; sayılar asla metin üretiminden gelmez). */
const { formatKurus } = require("./numbers");
const { splitYmd, weekdayOf, addDays } = require("./datetime");

const DAYS = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"];
const MON = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];
const MON_S = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"];

/** "2026-11-21" → "Cumartesi 21 Kasım" (yıl bugünden farklıysa yıl da yazılır) */
function fmtDate(ymd, todayYmd) {
  const { y, m, d } = splitYmd(ymd);
  const yr = todayYmd && splitYmd(todayYmd).y !== y ? ` ${y}` : "";
  return `${DAYS[weekdayOf(ymd)]} ${d} ${MON[m - 1]}${yr}`;
}
function fmtDateShort(ymd) { const { m, d } = splitYmd(ymd); return `${d} ${MON_S[m - 1]}`; }

/** Mutlak an (Date | ISO) → İstanbul {date:"YYYY-MM-DD", time:"HH:MM"} */
function istParts(dt) {
  const d = new Date(dt);
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul", hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).formatToParts(d).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}` };
}
const fmtAt = (dt, todayYmd) => { const p = istParts(dt); return `${fmtDate(p.date, todayYmd)} ${p.time}`; };
const kurus = (n) => formatKurus(n);

/** 1 → "1 randevu", çoğul eki yok (Türkçe sayıdan sonra tekil kalır) */
const count = (n, noun) => `${n} ${noun}`;

/** "Ahmet Yılmaz" → "ahmet yilmaz" benzeri katlama (eşleştirme için) */
module.exports = { DAYS, MON, MON_S, fmtDate, fmtDateShort, istParts, fmtAt, kurus, count, addDays };
