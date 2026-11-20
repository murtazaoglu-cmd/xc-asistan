/** Bildirim tercihleri: okuma (varsayılan + kuruluş saatleriyle birleştirilmiş), doğrulama, kayıt. */
const db = require("../db");
const clock = require("./clock");
const { orgIdForUser } = require("./org");

const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;
const hhmm = (v) => (v == null ? null : String(v).slice(0, 5));
const DEFAULTS = { enabled: true, tz: "Europe/Istanbul", morning_enabled: true, evening_enabled: true, quiet_enabled: true, quiet_start: "21:30", quiet_end: "07:00", weekdays: 63, channels: { push: true, inbox: true }, categories: {}, max_proactive_per_day: 5, critical_in_quiet: false };

const maskToDays = (m) => [1, 2, 3, 4, 5, 6, 7].filter((d) => m & (1 << (d - 1)));
const daysToMask = (days) => days.reduce((m, d) => m | (1 << (d - 1)), 0);

async function orgTimes(orgId) {
  const { rows } = await db.query("SELECT briefing_time, closing_time, timezone FROM org_settings WHERE org_id = $1", [orgId]);
  return rows[0] ? { morning: hhmm(rows[0].briefing_time), evening: hhmm(rows[0].closing_time), tz: rows[0].timezone } : { morning: "07:30", evening: "18:30", tz: "Europe/Istanbul" };
}

/** Etkin tercihler: satır yoksa varsayılan; morning/evening_time NULL ise kuruluş saatleri */
function effective(row, org) {
  const r = row || {};
  return {
    enabled: r.enabled ?? DEFAULTS.enabled,
    tz: r.tz || org.tz || DEFAULTS.tz,
    morning_enabled: r.morning_enabled ?? DEFAULTS.morning_enabled,
    evening_enabled: r.evening_enabled ?? DEFAULTS.evening_enabled,
    morning_time: hhmm(r.morning_time) || org.morning,
    evening_time: hhmm(r.evening_time) || org.evening,
    quiet_enabled: r.quiet_enabled ?? DEFAULTS.quiet_enabled,
    quiet_start: hhmm(r.quiet_start) || DEFAULTS.quiet_start,
    quiet_end: hhmm(r.quiet_end) || DEFAULTS.quiet_end,
    weekdays: maskToDays(r.weekdays ?? DEFAULTS.weekdays),
    channels: { ...DEFAULTS.channels, ...(r.channels || {}) },
    categories: r.categories || {},
    max_proactive_per_day: r.max_proactive_per_day ?? DEFAULTS.max_proactive_per_day,
    critical_in_quiet: r.critical_in_quiet ?? DEFAULTS.critical_in_quiet,
  };
}

async function getPrefs(userId) {
  const orgId = await orgIdForUser(userId);
  const [{ rows }, org] = await Promise.all([db.query("SELECT * FROM notification_prefs WHERE user_id = $1", [userId]), orgTimes(orgId)]);
  const p = effective(rows[0], org);
  p.is_default = !rows[0];
  return p;
}

/** Gövdeyi doğrular → {values} ya da {error}. Kısmi güncelleme: yalnız gelen alanlar. */
function validate(body) {
  const b = body && typeof body === "object" && !Array.isArray(body) ? body : null;
  if (!b) return { error: "Geçersiz gövde." };
  const v = {};
  const bool = (k) => { if (b[k] !== undefined) { if (typeof b[k] !== "boolean") return `${k} true/false olmalı.`; v[k] = b[k]; } };
  for (const k of ["enabled", "morning_enabled", "evening_enabled", "quiet_enabled", "critical_in_quiet"]) { const e = bool(k); if (e) return { error: e }; }
  for (const k of ["morning_time", "evening_time"]) {
    if (b[k] !== undefined) { if (b[k] !== null && !HHMM.test(b[k])) return { error: `${k} SS:DD biçiminde olmalı (ör. 07:30) ya da null (kuruluş varsayılanı).` }; v[k] = b[k]; }
  }
  for (const k of ["quiet_start", "quiet_end"]) {
    if (b[k] !== undefined) { if (typeof b[k] !== "string" || !HHMM.test(b[k])) return { error: `${k} SS:DD biçiminde olmalı.` }; v[k] = b[k]; }
  }
  if (b.tz !== undefined) { if (typeof b.tz !== "string" || !clock.isValidTimezone(b.tz)) return { error: "Geçersiz saat dilimi (tz)." }; v.tz = b.tz; }
  if (b.weekdays !== undefined) {
    const w = b.weekdays;
    if (!Array.isArray(w) || w.length > 7 || !w.every((d) => Number.isInteger(d) && d >= 1 && d <= 7)) return { error: "weekdays 1 (Pzt) … 7 (Paz) arası tam sayı dizisi olmalı." };
    v.weekdays = daysToMask([...new Set(w)]);
  }
  if (b.channels !== undefined) {
    const c = b.channels;
    if (!c || typeof c !== "object" || Array.isArray(c) || !Object.entries(c).every(([k, x]) => ["push", "inbox", "webpush", "email"].includes(k) && typeof x === "boolean")) return { error: "channels {push,inbox,webpush,email: true|false} olmalı." };
    v.channels = c;
  }
  if (b.categories !== undefined) {
    const c = b.categories;
    if (!c || typeof c !== "object" || Array.isArray(c) || Object.keys(c).length > 40 || !Object.entries(c).every(([k, x]) => /^[a-z0-9_.-]{1,40}$/i.test(k) && typeof x === "boolean")) return { error: "categories {tür: true|false} olmalı." };
    v.categories = c;
  }
  if (b.max_proactive_per_day !== undefined) {
    if (!Number.isInteger(b.max_proactive_per_day) || b.max_proactive_per_day < 0 || b.max_proactive_per_day > 50) return { error: "max_proactive_per_day 0..50 arası tam sayı olmalı." };
    v.max_proactive_per_day = b.max_proactive_per_day;
  }
  return { values: v };
}

async function savePrefs(userId, values) {
  const orgId = await orgIdForUser(userId);
  const cols = Object.keys(values);
  const params = [userId, orgId, ...cols.map((c) => (c === "channels" || c === "categories" ? JSON.stringify(values[c]) : values[c]))];
  const names = ["user_id", "org_id", ...cols];
  const ph = names.map((_, i) => `$${i + 1}`);
  const upd = cols.map((c) => `${c} = EXCLUDED.${c}`).concat("updated_at = now()").join(", ");
  await db.query(`INSERT INTO notification_prefs (${names.join(",")}) VALUES (${ph.join(",")}) ON CONFLICT (user_id) DO UPDATE SET ${upd}`, params);
  return getPrefs(userId);
}

/** Sessiz saat: şu an sessiz pencerede ise penceranın bittiği UTC anı, değilse null */
function quietUntil(now, p) {
  if (!p.quiet_enabled) return null;
  const date = clock.zonedDateStr(now, p.tz);
  const startT = p.quiet_start, endT = p.quiet_end;
  if (startT === endT) return null;
  const t = new Intl.DateTimeFormat("en-GB", { timeZone: p.tz, hourCycle: "h23", hour: "2-digit", minute: "2-digit" }).format(now);
  const inQuiet = startT < endT ? (t >= startT && t < endT) : (t >= startT || t < endT);
  if (!inQuiet) return null;
  const endToday = clock.zonedToUtc(date, endT, p.tz);
  return endToday > now ? endToday : clock.zonedToUtc(clock.addDays(date, 1), endT, p.tz);
}

module.exports = { getPrefs, savePrefs, validate, effective, orgTimes, quietUntil, maskToDays, DEFAULTS };
