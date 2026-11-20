/** Brifing/kapanış ortak yardımcıları: kişi kısayolları (ara / WhatsApp / yol tarifi), gün türü, metin birleştirme. */
const tr = require("../text/tr");
const deps = require("../facts/deps");
const { waDigits, telUri } = require("../manager/rules/_util");
const clock = require("../clock");

function contactActions(phone, lat, lng, address) {
  const d = waDigits(phone);
  let directions = null;
  if (lat != null && lng != null) directions = `geo:${lat},${lng}?q=${lat},${lng}`;
  else if (address) directions = `geo:0,0?q=${encodeURIComponent(address)}`;
  return { call: telUri(phone), whatsapp: d ? `https://wa.me/${d}` : null, directions };
}

function apptItem(a) {
  const who = a.customer_name || "Müşteri";
  const parts = [a.type, a.address].filter(Boolean);
  return {
    id: a.id, time: a.time, scheduled_at: a.scheduled_at, type: a.type, status: a.status, customer_name: a.customer_name, customer_phone: a.customer_phone, service: a.service,
    address: a.address, offer_id: a.offer_id, project_id: a.project_id,
    summary: `${a.time} ${who}${parts.length ? ` (${parts.join(", ")})` : ""}`,
    actions: contactActions(a.customer_phone, a.lat, a.lng, a.address),
  };
}

/** Pazar ve resmî tatil (holidays_tr varsa) → {kind:'pazar'|'tatil'|null, name} */
async function dayKind(dateStr, tz = clock.IST) {
  const hol = await deps.holidayName(dateStr);
  if (hol) return { kind: "tatil", name: hol };
  if (clock.zonedWeekday(clock.zonedToUtc(dateStr, "12:00", tz), tz) === 7) return { kind: "pazar", name: "Pazar" };
  return { kind: null, name: null };
}

const dateHeader = (ymd) => `${tr.weekdayName(ymd)}, ${tr.formatDate(ymd)}`;

module.exports = { contactActions, apptItem, dayKind, dateHeader };
