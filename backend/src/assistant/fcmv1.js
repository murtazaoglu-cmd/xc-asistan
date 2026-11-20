/**
 * FCM HTTP v1 istemcisi (ek paket yok: jsonwebtoken + yerleşik fetch).
 * Yapılandırma (HEPSİ opsiyonel — yoksa FCM "devre dışı" olur, bildirimler kutuda 'beklemede' kalır):
 *   FCM_SERVICE_ACCOUNT_FILE=/yol/servis-hesabi.json   ya da
 *   FCM_SERVICE_ACCOUNT_JSON='{...}' (ham JSON veya base64)
 *   FCM_PROJECT_ID (opsiyonel; yoksa servis hesabındaki project_id), FCM_API_BASE (test: sahte sunucu)
 */
const fs = require("fs");
const jwt = require("jsonwebtoken");

let cfgCache; // undefined = hesaplanmadı
function loadConfig(force = false) {
  if (cfgCache !== undefined && !force) return cfgCache;
  let raw = null;
  try {
    if (process.env.FCM_SERVICE_ACCOUNT_FILE) raw = fs.readFileSync(process.env.FCM_SERVICE_ACCOUNT_FILE, "utf8");
    else if (process.env.FCM_SERVICE_ACCOUNT_JSON) {
      const s = process.env.FCM_SERVICE_ACCOUNT_JSON.trim();
      raw = s.startsWith("{") ? s : Buffer.from(s, "base64").toString("utf8");
    }
  } catch (e) { console.error("FCM servis hesabı okunamadı:", e.message); }
  cfgCache = null;
  if (raw) {
    try {
      const j = JSON.parse(raw);
      if (j.client_email && j.private_key) {
        cfgCache = { clientEmail: j.client_email, privateKey: j.private_key, projectId: process.env.FCM_PROJECT_ID || j.project_id,
          tokenUri: j.token_uri || "https://oauth2.googleapis.com/token", apiBase: process.env.FCM_API_BASE || "https://fcm.googleapis.com" };
        if (!cfgCache.projectId) cfgCache = null;
      }
    } catch (e) { console.error("FCM servis hesabı JSON'u geçersiz:", e.message); }
  }
  return cfgCache;
}
const isEnabled = () => !!loadConfig();
function _reset() { cfgCache = undefined; tokenCache = null; }

let tokenCache = null; // {token, exp}
async function accessToken(cfg, force = false) {
  if (!force && tokenCache && tokenCache.exp > Date.now() + 60000) return tokenCache.token;
  const iat = Math.floor(Date.now() / 1000);
  const assertion = jwt.sign({ iss: cfg.clientEmail, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: cfg.tokenUri, iat, exp: iat + 3600 }, cfg.privateKey, { algorithm: "RS256" });
  const r = await fetch(cfg.tokenUri, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }), signal: AbortSignal.timeout(10000) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) throw new Error(`FCM erişim jetonu alınamadı (${r.status})`);
  tokenCache = { token: j.access_token, exp: Date.now() + (Number(j.expires_in) || 3600) * 1000 };
  return tokenCache.token;
}

/** Tek cihaza gönder. Dönüş: {ok:true} | {ok:false, permanent:boolean, invalidToken:boolean, error} */
async function send(deviceToken, msg, retried401 = false) {
  const cfg = loadConfig();
  if (!cfg) return { ok: false, permanent: false, invalidToken: false, error: "fcm_disabled" };
  let at;
  try { at = await accessToken(cfg); } catch (e) { return { ok: false, permanent: false, invalidToken: false, error: e.message }; }
  const data = {};
  for (const [k, v] of Object.entries(msg.data || {})) data[k] = typeof v === "string" ? v : JSON.stringify(v);
  const body = { message: { token: deviceToken, notification: { title: msg.title, body: msg.body }, data,
    android: { priority: "HIGH" }, apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } } } };
  let r;
  try {
    r = await fetch(`${cfg.apiBase}/v1/projects/${encodeURIComponent(cfg.projectId)}/messages:send`, { method: "POST",
      headers: { Authorization: `Bearer ${at}`, "Content-Type": "application/json" }, body: JSON.stringify(body), signal: AbortSignal.timeout(10000) });
  } catch (e) { return { ok: false, permanent: false, invalidToken: false, error: "ağ hatası: " + e.message }; }
  if (r.ok) return { ok: true };
  const j = await r.json().catch(() => ({}));
  const st = j.error && j.error.status; const emsg = (j.error && j.error.message) || "";
  const codes = ((j.error && j.error.details) || []).map((d) => d.errorCode).filter(Boolean);
  if (r.status === 401 && !retried401) { tokenCache = null; return send(deviceToken, msg, true); }
  if (r.status === 404 || codes.includes("UNREGISTERED") || st === "NOT_FOUND") return { ok: false, permanent: true, invalidToken: true, error: "UNREGISTERED" };
  if (r.status === 400 && /registration token|not a valid FCM/i.test(emsg)) return { ok: false, permanent: true, invalidToken: true, error: "INVALID_TOKEN" };
  if (r.status === 400 || r.status === 403) return { ok: false, permanent: true, invalidToken: false, error: `${st || r.status}: ${emsg}`.slice(0, 300) };
  return { ok: false, permanent: false, invalidToken: false, error: `${st || r.status}: ${emsg}`.slice(0, 300) }; // 429, 5xx, UNAVAILABLE…
}

module.exports = { loadConfig, isEnabled, send, _reset };
