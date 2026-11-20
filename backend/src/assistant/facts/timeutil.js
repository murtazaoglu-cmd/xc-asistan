/** İş saati hesabı: Pzt–Cmt 09:00–18:00 (İstanbul). Cevapsız talep yaşı (M6b) "iş saati içinde" ölçülür. */
const clock = require("../clock");

const WORK_START = "09:00", WORK_END = "18:00";

/** [from,to) aralığının iş saati penceresiyle kesişimi (saat, ondalıklı). Pazar sayılmaz. */
function workHoursBetween(from, to, tz = clock.IST) {
  const a = new Date(from), b = new Date(to);
  if (!(b > a)) return 0;
  let day = clock.zonedDateStr(a, tz);
  const lastDay = clock.zonedDateStr(b, tz);
  let ms = 0;
  for (let i = 0; i < 90 && day <= lastDay; i++, day = clock.addDays(day, 1)) {
    if (clock.zonedWeekday(clock.zonedToUtc(day, "12:00", tz), tz) === 7) continue;
    const ws = clock.zonedToUtc(day, WORK_START, tz), we = clock.zonedToUtc(day, WORK_END, tz);
    const s = Math.max(ws.getTime(), a.getTime()), e = Math.min(we.getTime(), b.getTime());
    if (e > s) ms += e - s;
  }
  return ms / 3600000;
}
module.exports = { workHoursBetween, WORK_START, WORK_END };
