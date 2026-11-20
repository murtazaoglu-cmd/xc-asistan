/**
 * Saat dilimi bağımsız takvim tarihi yardımcıları. Tarihler "YYYY-MM-DD" metni olarak taşınır;
 * aritmetik UTC üzerinden yapılır (Europe/Istanbul'da yaz saati yoktur, ama sunucu TZ'sine bağımlı olmamak için).
 */
const ISO_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Gerçek bir takvim günü mü ("2026-02-30" geçersiz) */
function isValidIsoDate(s) {
  if (typeof s !== "string") return false;
  const m = ISO_RE.exec(s);
  if (!m) return false;
  const y = +m[1], mo = +m[2], d = +m[3];
  if (y < 1900 || y > 2200 || mo < 1 || mo > 12 || d < 1) return false;
  return d <= daysInMonth(y, mo);
}
const daysInMonth = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate(); // m: 1..12
const pad = (n, w = 2) => String(n).padStart(w, "0");
const fmt = (y, m, d) => `${pad(y, 4)}-${pad(m)}-${pad(d)}`;
const toUtc = (s) => { const m = ISO_RE.exec(s); return Date.UTC(+m[1], +m[2] - 1, +m[3]); };
const fromUtc = (ms) => { const d = new Date(ms); return fmt(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate()); };

function addDays(s, n) { return fromUtc(toUtc(s) + n * 86400000); }
function daysBetween(a, b) { return Math.round((toUtc(b) - toUtc(a)) / 86400000); } // b − a
/** 0 = Pazar … 6 = Cumartesi */
function weekday(s) { return new Date(toUtc(s)).getUTCDay(); }
/** (y, m 1..12) ayına n ay ekle → {y, m} */
function addMonths(y, m, n) { const t = y * 12 + (m - 1) + n; return { y: Math.floor(t / 12), m: (t % 12) + 1 }; }
/** Ay içi güne sıkıştırarak (31 → ayın son günü) tarih üret. day: sayı ya da "last" */
function dateIn(y, m, day) {
  const dim = daysInMonth(y, m);
  const d = day === "last" ? dim : Math.min(Number(day), dim);
  return fmt(y, m, d);
}
/** İstanbul takvimine göre bugün (YYYY-MM-DD) */
function todayIstanbul(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}
/** timestamptz/Date → İstanbul takvim günü */
const dayOf = (v) => (v instanceof Date ? todayIstanbul(v) : String(v).slice(0, 10));

module.exports = { isValidIsoDate, daysInMonth, fmt, addDays, daysBetween, weekday, addMonths, dateIn, todayIstanbul, dayOf, pad };
