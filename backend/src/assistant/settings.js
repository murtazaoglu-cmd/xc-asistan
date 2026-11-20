/** Kuruluş ayarları / sektör şablonları / özellik bayrakları / sürüm bilgisi (GET-PATCH /api/config için servis). */
const crypto = require("crypto");
const db = require("../db");
const clock = require("./clock");
const { orgIdForUser } = require("./org");
const pkg = require("../../package.json");

const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;
const LISTS = ["service_types", "appointment_types", "expense_categories"];
const hhmm = (v) => String(v).slice(0, 5);

async function loadOrg(orgId) {
  const { rows } = await db.query(
    `SELECT o.id, o.name, o.sector_key AS org_sector, s.* FROM organizations o LEFT JOIN org_settings s ON s.org_id = o.id WHERE o.id = $1`, [orgId]);
  const r = rows[0];
  if (!r) return null;
  if (r.org_id) return r;
  // ayar satırı yoksa 'genel' şablon varsayılanları
  const { rows: t } = await db.query("SELECT * FROM sector_templates WHERE key = 'genel'");
  const g = t[0] || {};
  return { ...r, brand: { name: r.name }, sector_dictionary: { terms: g.dictionary || {} }, service_types: g.service_types || [], appointment_types: g.appointment_types || [],
    expense_categories: g.expense_categories || [], timezone: "Europe/Istanbul", briefing_time: "07:30", closing_time: "18:30", sector_key: "genel" };
}

async function flagsFor(orgId, userId) {
  const { rows } = await db.query("SELECT key, org_id, enabled, rollout_percent FROM feature_flags WHERE org_id IS NULL OR org_id = $1", [orgId]);
  const pick = new Map();
  for (const r of rows) { const cur = pick.get(r.key); if (!cur || (r.org_id && !cur.org_id)) pick.set(r.key, r); } // kuruluş ayarı genelin üstüne geçer
  const out = {};
  for (const [k, r] of pick) {
    let on = r.enabled;
    if (on && r.rollout_percent < 100) {
      const b = parseInt(crypto.createHash("sha1").update(`${userId}:${k}`).digest("hex").slice(0, 8), 16) % 100;
      on = b < r.rollout_percent;
    }
    out[k] = on;
  }
  return out;
}

function serverInfo() {
  const env = process.env;
  return {
    version: pkg.version, apiVersion: 1, time: clock.now().toISOString(),
    minAppVersion: env.APP_MIN_VERSION || null, latestAppVersion: env.APP_LATEST_VERSION || null,
    storeUrls: { android: env.APP_STORE_URL_ANDROID || null, ios: env.APP_STORE_URL_IOS || null },
    maintenance: { enabled: env.MAINTENANCE_MODE === "true", message: env.MAINTENANCE_MESSAGE || null },
  };
}

async function buildConfig(user) {
  const orgId = await orgIdForUser(user.id);
  const [o, flags] = await Promise.all([loadOrg(orgId), flagsFor(orgId, user.id)]);
  return {
    server: serverInfo(),
    org: { id: o.id, name: o.name, sector_key: o.sector_key || o.org_sector || null },
    brand: { name: o.name, logo_url: null, primary_color: null, ...(o.brand || {}) },
    sector_dictionary: o.sector_dictionary && o.sector_dictionary.terms ? o.sector_dictionary : { terms: {} },
    lists: { service_types: o.service_types, appointment_types: o.appointment_types, expense_categories: o.expense_categories },
    settings: { timezone: o.timezone, briefing_time: hhmm(o.briefing_time), closing_time: hhmm(o.closing_time) },
    flags,
  };
}

function cleanList(v, name) {
  if (!Array.isArray(v) || v.length > 50) return { error: `${name} en çok 50 öğeli bir dizi olmalı.` };
  const out = [];
  for (const x of v) {
    if (typeof x !== "string") return { error: `${name} yalnız metin içerebilir.` };
    const s = x.trim();
    if (!s || s.length > 40) return { error: `${name} öğeleri 1-40 karakter olmalı.` };
    if (/[\u0000-\u001f<>]/.test(s)) return { error: `${name} geçersiz karakter içeriyor.` };
    if (!out.some((y) => y.toLowerCase() === s.toLowerCase())) out.push(s);
  }
  return { value: out };
}

const ALLOWED = ["brand", "sector_dictionary", ...LISTS, "timezone", "briefing_time", "closing_time"];
/** PATCH gövdesini doğrular → {values} | {error} */
function validatePatch(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return { error: "Geçersiz gövde." };
  const keys = Object.keys(body);
  if (keys.length === 0) return { error: "Değiştirilecek alan yok." };
  const bad = keys.find((k) => !ALLOWED.includes(k));
  if (bad) return { error: `Bilinmeyen alan: ${bad.slice(0, 40)}` };
  const v = {};
  if (body.brand !== undefined) {
    const b = body.brand;
    if (!b || typeof b !== "object" || Array.isArray(b)) return { error: "brand nesne olmalı." };
    const nb = {};
    for (const k of Object.keys(b)) {
      if (!["name", "logo_url", "primary_color"].includes(k)) return { error: `brand.${k.slice(0, 30)} bilinmiyor.` };
    }
    if (b.name !== undefined) { if (typeof b.name !== "string" || !b.name.trim() || b.name.trim().length > 80) return { error: "brand.name 1-80 karakter olmalı." }; nb.name = b.name.trim(); }
    if (b.logo_url !== undefined) {
      if (b.logo_url !== null && (typeof b.logo_url !== "string" || b.logo_url.length > 500 || !/^https:\/\/[^\s]+$/i.test(b.logo_url))) return { error: "brand.logo_url https:// ile başlayan bir adres (≤500) ya da null olmalı." };
      nb.logo_url = b.logo_url;
    }
    if (b.primary_color !== undefined) {
      if (b.primary_color !== null && (typeof b.primary_color !== "string" || !/^#[0-9a-fA-F]{6}$/.test(b.primary_color))) return { error: "brand.primary_color #RRGGBB biçiminde olmalı." };
      nb.primary_color = b.primary_color;
    }
    v.brand = nb;
  }
  if (body.sector_dictionary !== undefined) {
    const t = body.sector_dictionary && body.sector_dictionary.terms;
    if (!t || typeof t !== "object" || Array.isArray(t) || Object.keys(body.sector_dictionary).length !== 1) return { error: "sector_dictionary {terms:{anahtar:'Ad'}} olmalı." };
    const ks = Object.keys(t);
    if (ks.length > 60) return { error: "En çok 60 terim." };
    for (const k of ks) {
      if (!/^[a-z][a-z0-9_]{0,39}$/.test(k)) return { error: `Terim anahtarı geçersiz: ${k.slice(0, 40)}` };
      if (t[k] !== null && (typeof t[k] !== "string" || !t[k].trim() || t[k].length > 60 || /[\u0000-\u001f<>]/.test(t[k]))) return { error: `Terim değeri 1-60 karakter olmalı (silmek için null): ${k}` };
    }
    v.terms = t; // null → silinir
  }
  for (const l of LISTS) if (body[l] !== undefined) { const r = cleanList(body[l], l); if (r.error) return r; v[l] = r.value; }
  if (body.timezone !== undefined) { if (!clock.isValidTimezone(body.timezone)) return { error: "Geçersiz saat dilimi." }; v.timezone = body.timezone; }
  for (const k of ["briefing_time", "closing_time"]) if (body[k] !== undefined) { if (typeof body[k] !== "string" || !HHMM.test(body[k])) return { error: `${k} SS:DD biçiminde olmalı.` }; v[k] = body[k]; }
  return { values: v };
}

async function ensureSettingsRow(client, orgId) {
  await client.query(
    `INSERT INTO org_settings (org_id, brand, sector_dictionary, service_types, appointment_types, expense_categories, sector_key)
     SELECT o.id, jsonb_build_object('name', o.name), jsonb_build_object('terms', t.dictionary), t.service_types, t.appointment_types, t.expense_categories, t.key
       FROM organizations o JOIN sector_templates t ON t.key = 'genel' WHERE o.id = $1 ON CONFLICT (org_id) DO NOTHING`, [orgId]);
}

async function patchSettings(orgId, v) {
  const client = await db.pool.connect();
  try {
    await client.query("BEGIN");
    await ensureSettingsRow(client, orgId);
    const { rows } = await client.query("SELECT * FROM org_settings WHERE org_id = $1 FOR UPDATE", [orgId]);
    const cur = rows[0];
    const sets = []; const params = [orgId];
    const add = (col, val, json) => { params.push(json ? JSON.stringify(val) : val); sets.push(`${col} = $${params.length}`); };
    if (v.brand) {
      const nb = { ...(cur.brand || {}), ...v.brand };
      add("brand", nb, true);
      if (v.brand.name) await client.query("UPDATE organizations SET name = $2 WHERE id = $1", [orgId, v.brand.name]);
    }
    if (v.terms) {
      const terms = { ...((cur.sector_dictionary && cur.sector_dictionary.terms) || {}) };
      for (const [k, val] of Object.entries(v.terms)) { if (val === null) delete terms[k]; else terms[k] = val.trim(); }
      add("sector_dictionary", { terms }, true);
    }
    for (const l of LISTS) if (v[l]) add(l, v[l], true);
    if (v.timezone) add("timezone", v.timezone);
    if (v.briefing_time) add("briefing_time", v.briefing_time);
    if (v.closing_time) add("closing_time", v.closing_time);
    sets.push("updated_at = now()");
    await client.query(`UPDATE org_settings SET ${sets.join(", ")} WHERE org_id = $1`, params);
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
}

async function listTemplates() {
  const { rows } = await db.query("SELECT key, name, description, dictionary, service_types, appointment_types, expense_categories, is_default FROM sector_templates ORDER BY sort_order, key");
  return rows;
}

const union = (a, b) => { const out = [...a]; for (const x of b) if (!out.some((y) => String(y).toLowerCase() === String(x).toLowerCase())) out.push(x); return out; };
/** Şablonu uygular. Yalnız ayarlar değişir; mevcut randevu/gider/teklif kayıtlarına DOKUNULMAZ. mode: replace (varsayılan) | merge */
async function applyTemplate(orgId, key, mode = "replace") {
  const { rows: t } = await db.query("SELECT * FROM sector_templates WHERE key = $1", [key]);
  if (!t[0]) return null;
  const tpl = t[0];
  const client = await db.pool.connect();
  try {
    await client.query("BEGIN");
    await ensureSettingsRow(client, orgId);
    const { rows } = await client.query("SELECT * FROM org_settings WHERE org_id = $1 FOR UPDATE", [orgId]);
    const cur = rows[0];
    const curTerms = (cur.sector_dictionary && cur.sector_dictionary.terms) || {};
    const terms = mode === "merge" ? { ...tpl.dictionary, ...curTerms } : { ...tpl.dictionary };
    const lst = (c, tv) => (mode === "merge" ? union(c || [], tv) : tv);
    await client.query(
      `UPDATE org_settings SET sector_dictionary = $2, service_types = $3, appointment_types = $4, expense_categories = $5, sector_key = $6, updated_at = now() WHERE org_id = $1`,
      [orgId, JSON.stringify({ terms }), JSON.stringify(lst(cur.service_types, tpl.service_types)), JSON.stringify(lst(cur.appointment_types, tpl.appointment_types)), JSON.stringify(lst(cur.expense_categories, tpl.expense_categories)), tpl.key]);
    await client.query("UPDATE organizations SET sector_key = $2 WHERE id = $1", [orgId, tpl.key]);
    await client.query("COMMIT");
  } catch (e) { await client.query("ROLLBACK").catch(() => {}); throw e; } finally { client.release(); }
  return tpl;
}

module.exports = { buildConfig, validatePatch, patchSettings, listTemplates, applyTemplate, flagsFor, serverInfo };
