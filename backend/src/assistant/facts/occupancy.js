/**
 * Doluluk: önümüzdeki N iş gününde (Pzt–Cmt; Pazar ve resmî tatil atlanır) randevusu olmayan günler + açık teklif sayısı.
 * Kapsam: 'biz' (admin/muhasebe işletme; ortak yalnız kendi).
 */
const clock = require("../clock");
const tr = require("../text/tr");
const deps = require("./deps");
const agenda = require("./agenda");
const funnel = require("./funnel");

async function occupancy(ctx, { fromDate = clock.addDays(ctx.date, 1), workdays = 7 } = {}) {
  const days = [];
  let d = fromDate;
  for (let i = 0; i < 40 && days.length < workdays; i++, d = clock.addDays(d, 1)) {
    const wd = clock.zonedWeekday(clock.zonedToUtc(d, "12:00", ctx.tz), ctx.tz);
    if (wd === 7) continue;
    if (await deps.holidayName(d)) continue;
    days.push({ date: d, weekday: tr.weekdayName(d), count: 0, empty: true });
  }
  if (days.length === 0) return { from: fromDate, days: [], empty_days: 0, empty_dates: [], open_offers: 0 };
  const from = clock.zonedToUtc(days[0].date, "00:00", ctx.tz), to = clock.zonedToUtc(clock.addDays(days[days.length - 1].date, 1), "00:00", ctx.tz);
  const appts = await agenda.appointmentsBetween(ctx, from, to, { mode: "biz", limit: 1000 });
  const byDate = new Map();
  for (const a of appts) if (a.state !== "iptal") byDate.set(a.date, (byDate.get(a.date) || 0) + 1);
  for (const x of days) { x.count = byDate.get(x.date) || 0; x.empty = x.count === 0; }
  const empty = days.filter((x) => x.empty);
  return { from: fromDate, to: days[days.length - 1].date, days, empty_days: empty.length, empty_dates: empty.map((x) => x.date), open_offers: await funnel.openOfferCount(ctx, "biz") };
}
module.exports = { occupancy };
