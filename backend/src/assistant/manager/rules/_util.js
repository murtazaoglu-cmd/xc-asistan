/** Kural yardımcıları: aday (candidate) kurucu, ağırlıklar, aksiyon metadatası kurucuları. */
const clock = require("../../clock");

const SEV_RANK = { info: 1, warn: 2, critical: 3 };

/**
 * Aday: değerlendiricinin ürettiği, metne çevrilmemiş insight.
 * metrics: [{key, label, value, unit}]  unit ∈ kurus | count | bp | days | hours | date | text  (sayısal dayanak — "Neden?")
 * actions: aksiyon NİYETİ listesi (buildActions ile etiket/gövde alır)
 */
function cand(rule, severity, fingerprint, o = {}) {
  return { rule, severity, fingerprint, entity: o.entity || null, vars: o.vars || {}, metrics: o.metrics || [], refs: o.refs || [], score: Math.max(0, Math.round(o.score || 0)), actions: o.actions || [] };
}
const m = (key, label, value, unit) => ({ key, label, value, unit });

/** Telefon → wa.me için uluslararası rakam dizisi (TR varsayımı: 0532… → 90532…) */
function waDigits(phone) {
  let d = String(phone || "").replace(/\D/g, "");
  if (!d) return null;
  if (d.startsWith("00")) d = d.slice(2);
  else if (d.startsWith("0")) d = "90" + d.slice(1);
  else if (d.length === 10) d = "90" + d;
  return d.length >= 11 ? d : null;
}
const telUri = (phone) => { const d = waDigits(phone); return d ? `tel:+${d}` : null; };

/** Yarın 09:00 (İstanbul) UTC ISO — önerilen hatırlatma zamanı */
const tomorrowAt = (dateStr, hhmm = "09:00", plusDays = 1, tz = clock.IST) => clock.zonedToUtc(clock.addDays(dateStr, plusDays), hhmm, tz).toISOString();

/** Aksiyon niyeti kurucuları (etiketler templates.buildActions'ta Türkçeleştirilir) */
const A = {
  reminder: (o) => ({ type: "reminder", title: o.title, project_id: o.project_id || null, offer_id: o.offer_id || null, phone: o.phone || null, name: o.name || null, plusDays: o.plusDays == null ? 1 : o.plusDays }),
  call: (o) => ({ type: "call", phone: o.phone || null, name: o.name || null, offer_id: o.offer_id || null, project_id: o.project_id || null }),
  whatsapp: (o) => ({ type: "whatsapp", template: o.template, phone: o.phone || null, name: o.name || null, vars: o.vars || {}, offer_id: o.offer_id || null, project_id: o.project_id || null }),
  appointment: (o = {}) => ({ type: "appointment", name: o.name || null, phone: o.phone || null, offer_id: o.offer_id || null, project_id: o.project_id || null, dates: o.dates || [] }),
  open: (entity_type, id) => ({ type: "open", entity_type, id }),
  callList: (items) => ({ type: "call_list", items }),
  screen: (screen, params) => ({ type: "screen", screen, params: params || {} }),
};

module.exports = { SEV_RANK, cand, m, waDigits, telUri, tomorrowAt, A };
