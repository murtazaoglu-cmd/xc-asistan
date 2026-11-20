/**
 * Saat — TÜM zaman mantığı buradan geçer (sahte saatle test edilebilirlik).
 *
 * Sözleşme (imzalar sabit; diğer paketler buna dayanır):
 *   now()                 → Date  (sahte saat kuruluysa o, yoksa gerçek şimdi)
 *   istanbulDay(d?)       → Date  İstanbul gününün BAŞLANGICI (İstanbul 00:00'ın UTC anı)
 *   istanbulDateStr(d?)   → "YYYY-MM-DD" (İstanbul takvim günü)
 *   setFake(d)            → sahte saati kur (Date | ISO metin | ms); reset() → gerçek saate dön
 * Ek yardımcılar: istanbulWeekday(d?) (1=Pzt … 7=Paz), zonedDateStr(d, tz), zonedToUtc("YYYY-MM-DD","HH:MM", tz),
 *   zonedWeekday(d, tz), addDays("YYYY-MM-DD", n), isFake().
 * Test amaçlı ASSISTANT_FAKE_NOW=<ISO> ortam değişkeni (yalnız NODE_ENV!=production) sürecin sahte saatini başlatır.
 */
const IST = "Europe/Istanbul";
let fake = null;

function toDate(d) {
  if (d === undefined || d === null) return now();
  const x = d instanceof Date ? d : new Date(d);
  if (Number.isNaN(x.getTime())) throw new Error("Geçersiz tarih: " + String(d));
  return x;
}
function now() { return fake ? new Date(fake.getTime()) : new Date(); }
function setFake(d) { fake = new Date(toDate(d === undefined ? new Date() : d).getTime()); return fake; }
function reset() { fake = null; }
function isFake() { return fake !== null; }

if (process.env.ASSISTANT_FAKE_NOW && process.env.NODE_ENV !== "production") {
  try { setFake(process.env.ASSISTANT_FAKE_NOW); } catch { /* yoksay */ }
}

const fmtCache = new Map();
function parts(d, tz) {
  let f = fmtCache.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-CA", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", weekday: "short" });
    fmtCache.set(tz, f);
  }
  const o = {};
  for (const p of f.formatToParts(d)) o[p.type] = p.value;
  return o;
}
function isValidTimezone(tz) {
  try { new Intl.DateTimeFormat("en-US", { timeZone: tz }); return typeof tz === "string" && tz.length > 0; } catch { return false; }
}
function zonedDateStr(d, tz = IST) { const p = parts(toDate(d), tz); return `${p.year}-${p.month}-${p.day}`; }
const WD = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };
function zonedWeekday(d, tz = IST) { return WD[parts(toDate(d), tz).weekday]; }
/** "YYYY-MM-DD" + "HH:MM" (verilen saat diliminde yerel) → UTC anı (Date). Saat atlaması/DST'de ilk geçerli ana oturur. */
function zonedToUtc(dateStr, timeStr, tz = IST) {
  const [y, mo, da] = dateStr.split("-").map(Number);
  const [h, mi] = String(timeStr).split(":").map(Number);
  let guess = Date.UTC(y, mo - 1, da, h, mi || 0, 0);
  for (let i = 0; i < 3; i++) {
    const p = parts(new Date(guess), tz);
    const asLocal = Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day), Number(p.hour), Number(p.minute), Number(p.second));
    const diff = Date.UTC(y, mo - 1, da, h, mi || 0, 0) - asLocal;
    if (diff === 0) break;
    guess += diff;
  }
  return new Date(guess);
}
function addDays(dateStr, n) {
  const [y, m, d] = dateStr.split("-").map(Number);
  const x = new Date(Date.UTC(y, m - 1, d + n));
  return x.toISOString().slice(0, 10);
}
function istanbulDateStr(d) { return zonedDateStr(d === undefined ? now() : d, IST); }
function istanbulDay(d) { return zonedToUtc(istanbulDateStr(d), "00:00", IST); }
function istanbulWeekday(d) { return zonedWeekday(d === undefined ? now() : d, IST); }

module.exports = { IST, now, setFake, reset, isFake, istanbulDay, istanbulDateStr, istanbulWeekday, zonedDateStr, zonedWeekday, zonedToUtc, addDays, isValidTimezone };
