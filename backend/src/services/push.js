const webpush = require("web-push");
const db = require("../db");
const fcm = require("./fcm");
const { isAllowedPushEndpoint } = require("./validate");
require("dotenv").config();

// VAPID anahtarları isteğe bağlıdır: yoksa web-push (tarayıcı bildirimi) KAPALI olur, sunucu yine başlar
// (eskiden anahtar yokken web-push "No key set vapidDetails.publicKey" ile süreci çökertiyordu).
const VAPID_ENABLED = !!(process.env.VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY);
if (VAPID_ENABLED) {
  webpush.setVapidDetails("mailto:info@controlx.com.tr", process.env.VAPID_PUBLIC_KEY, process.env.VAPID_PRIVATE_KEY);
} else {
  console.warn("UYARI: VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY tanımsız; web paneli tarayıcı bildirimleri kapalı (mobil FCM ve bildirim kutusu etkilenmez).");
}

const SEND_OPTIONS = { timeout: 10000, TTL: 3600 };

/** Eski/güvenilmeyen uç noktaları (SSRF) ele: izin verilmeyen abonelik ASLA çağrılmaz ve silinir */
async function onlySafe(rows) {
  const safe = [];
  for (const sub of rows) {
    if (isAllowedPushEndpoint(sub.endpoint)) safe.push(sub);
    else await db.query("DELETE FROM push_subscriptions WHERE id = $1", [sub.id]).catch(() => {});
  }
  return safe;
}

/**
 * Panele "Ana Ekrana Ekle" ile abone olmuş tüm admin cihazlarına
 * yeni teklif bildirimi gönderir.
 */
async function notifyNewOffer(offer) {
  // Yeni teklif bildirimi yalnızca teklifin sahibine; sahipsizse (web sitesinden) admin ve muhasebeye gider
  // Mobil (FCM) kancası — şimdilik boş; aynı alıcılar için çağrılır
  try {
    const { rows: rcpt } = await db.query(
      `SELECT id FROM users WHERE ($1::uuid IS NOT NULL AND id = $1) OR ($1::uuid IS NULL AND role IN ('admin','muhasebe'))`,
      [offer.owner_id || null]
    );
    await fcm.sendToUsers(rcpt.map((r) => r.id), {
      title: "Yeni Teklif Talebi",
      body: `${offer.name} — ${offer.service}${offer.region ? " · " + offer.region : ""}`,
      data: { type: "offer", id: offer.id },
    });
  } catch (err) { console.error("FCM kancası hatası:", err.message); }
  const { rows: allRows } = await db.query(
    `SELECT ps.* FROM push_subscriptions ps JOIN users u ON u.id = ps.user_id
     WHERE ($1::uuid IS NOT NULL AND ps.user_id = $1) OR ($1::uuid IS NULL AND u.role IN ('admin','muhasebe'))`,
    [offer.owner_id || null]
  );
  if (!VAPID_ENABLED) return { sent: 0 };
  const rows = await onlySafe(allRows);
  if (rows.length === 0) return { sent: 0 };

  const payload = JSON.stringify({
    title: "Yeni Teklif Talebi",
    body: `${offer.name} — ${offer.service}${offer.region ? " · " + offer.region : ""}`,
    url: "/",
    tag: "xcontrol-offer-" + offer.id,
  });

  let sent = 0;
  await Promise.all(
    rows.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          payload,
          SEND_OPTIONS
        );
        sent++;
      } catch (err) {
        // Abonelik artık geçersizse (410 Gone) sil
        if (err.statusCode === 410 || err.statusCode === 404) {
          await db.query("DELETE FROM push_subscriptions WHERE id = $1", [sub.id]);
        } else {
          console.error("Push gönderim hatası:", err.message);
        }
      }
    })
  );
  return { sent };
}

/**
 * Belirli bir kullanıcının ("Ana Ekrana Ekle" ile abone olduğu) cihazlarına özel bildirim gönderir.
 * Paylaşım, atama gibi kişiye özel olaylarda kullanılır.
 */
async function notifyUser(userId, title, body, url) {
  if (!userId) return { sent: 0 };
  try { await fcm.sendToUsers([userId], { title, body, url, data: { url: url || "/" } }); }
  catch (err) { console.error("FCM kancası hatası:", err.message); }
  if (!VAPID_ENABLED) return { sent: 0 };
  const rows = await onlySafe((await db.query("SELECT * FROM push_subscriptions WHERE user_id = $1", [userId])).rows);
  if (rows.length === 0) return { sent: 0 };

  const payload = JSON.stringify({ title, body, url: url || "/", tag: "xcontrol-share-" + Date.now() });

  let sent = 0;
  await Promise.all(
    rows.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          payload,
          SEND_OPTIONS
        );
        sent++;
      } catch (err) {
        if (err.statusCode === 410 || err.statusCode === 404) {
          await db.query("DELETE FROM push_subscriptions WHERE id = $1", [sub.id]);
        } else {
          console.error("Push gönderim hatası:", err.message);
        }
      }
    })
  );
  return { sent };
}

module.exports = { notifyNewOffer, notifyUser };
