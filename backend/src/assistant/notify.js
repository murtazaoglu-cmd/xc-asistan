/**
 * Bildirim servisi — notification_outbox'a İDEMPOTENT yazar. Gönderimi sender.js yapar; uygulama içi bildirim kutusu
 * (GET /api/assistant/inbox) her zaman buradan okur (FCM kapalıyken de çalışır).
 *
 *   notifyUser(userId, {type, title, body, data, dedupeKey, sendAt, priority, expiresAt}) → {id, deduped, status, notBefore}
 *     dedupeKey aynıysa ikinci kayıt oluşmaz (iş iki kez çalışsa da tek bildirim). dedupeKey verilmezse HER çağrı yeni bildirimdir.
 *     sendAt verilmezse: kullanıcının sessiz saatindeyse (kritik değilse) sessiz saat bitimine ertelenir.
 *     Kullanıcı bildirimi/türü kapattıysa kayıt 'iptal' olarak tutulur (dedupe korunur, kutuda görünmez).
 */
const crypto = require("crypto");
const db = require("../db");
const clock = require("./clock");
const prefsSvc = require("./prefs");
const { orgIdForUser } = require("./org");

async function notifyUser(userId, o = {}) {
  if (!userId) throw new Error("notifyUser: userId gerekli");
  const type = String(o.type || "genel").slice(0, 60);
  const title = String(o.title || "").slice(0, 200);
  if (!title) throw new Error("notifyUser: title gerekli");
  const body = String(o.body || "").slice(0, 2000);
  const priority = o.priority === "critical" ? "critical" : "normal";
  const dedupeKey = o.dedupeKey ? String(o.dedupeKey).slice(0, 300) : `auto:${crypto.randomUUID()}`;
  const now = clock.now();
  const orgId = await orgIdForUser(userId);
  const p = await prefsSvc.getPrefs(userId);

  let status = "beklemede", err = null, notBefore = o.sendAt ? new Date(o.sendAt) : now;
  if (Number.isNaN(notBefore.getTime())) throw new Error("notifyUser: geçersiz sendAt");
  if (p.enabled === false) { status = "iptal"; err = "kullanıcı bildirimleri kapattı"; }
  else if (p.categories && p.categories[type] === false) { status = "iptal"; err = "tür kapalı"; }
  else if (!o.sendAt && !(priority === "critical" && p.critical_in_quiet)) {
    const q = prefsSvc.quietUntil(now, p);
    if (q) notBefore = q;
  }

  const ins = await db.query(
    `INSERT INTO notification_outbox (org_id, user_id, type, title, body, data, priority, dedupe_key, not_before, expires_at, status, last_error)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
     ON CONFLICT (dedupe_key) DO NOTHING RETURNING id`,
    [orgId, userId, type, title, body, JSON.stringify(o.data || {}), priority, dedupeKey, notBefore, o.expiresAt || null, status, err]
  );
  if (ins.rows[0]) return { id: ins.rows[0].id, deduped: false, status, notBefore };
  const ex = await db.query("SELECT id, status, not_before FROM notification_outbox WHERE dedupe_key = $1", [dedupeKey]);
  return { id: ex.rows[0].id, deduped: true, status: ex.rows[0].status, notBefore: ex.rows[0].not_before };
}

module.exports = { notifyUser };
