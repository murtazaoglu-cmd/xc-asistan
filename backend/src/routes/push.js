const express = require("express");
const db = require("../db");
const { requireAuth } = require("../middleware/auth");
const { isAllowedPushEndpoint } = require("../services/validate");

const MAX_SUBSCRIPTIONS_PER_USER = 20;
const KEY_RE = /^[A-Za-z0-9_\-+/=]{16,200}$/;

const router = express.Router();

/** PUBLIC — Panelin abone olurken kullanacağı VAPID public key */
router.get("/vapid-public-key", (req, res) => {
  res.json({ publicKey: process.env.VAPID_PUBLIC_KEY || null });
});

/** ADMIN — Bu cihazı bildirim aboneliğine kaydet */
router.post("/subscribe", requireAuth, async (req, res) => {
  const { endpoint, keys } = req.body;
  if (!endpoint || !keys || !keys.p256dh || !keys.auth) {
    return res.status(400).json({ error: "Geçersiz abonelik verisi." });
  }
  // SSRF koruması: sunucu bu adrese kendisi istek atacağından yalnız https + bilinen push servisi alan adları kabul edilir (F-27)
  if (!isAllowedPushEndpoint(endpoint)) return res.status(400).json({ error: "Desteklenmeyen bildirim uç noktası." });
  if (typeof keys.p256dh !== "string" || typeof keys.auth !== "string" || !KEY_RE.test(keys.p256dh) || !KEY_RE.test(keys.auth)) {
    return res.status(400).json({ error: "Geçersiz abonelik anahtarları." });
  }
  const count = await db.query("SELECT COUNT(*)::int AS n FROM push_subscriptions WHERE user_id = $1 AND endpoint <> $2", [req.user.id, endpoint]);
  if (count.rows[0].n >= MAX_SUBSCRIPTIONS_PER_USER) return res.status(429).json({ error: "Bu hesap için çok fazla bildirim aboneliği var." });
  // Uç nokta tarayıcıya özel gizli bir adrestir; aynı tarayıcıda hesap değişince abonelik yeni kullanıcıya devredilir
  await db.query(
    `INSERT INTO push_subscriptions (endpoint, p256dh, auth, user_id)
     VALUES ($1,$2,$3,$4)
     ON CONFLICT (endpoint) DO UPDATE SET p256dh = $2, auth = $3, user_id = $4`,
    [endpoint, keys.p256dh, keys.auth, req.user.id]
  );
  res.status(201).json({ message: "Abonelik kaydedildi." });
});

/** ADMIN — Bu cihazın aboneliğini kaldır (yalnız kendi aboneliği) */
router.post("/unsubscribe", requireAuth, async (req, res) => {
  const { endpoint } = req.body;
  if (!endpoint || typeof endpoint !== "string") return res.status(400).json({ error: "endpoint gerekli." });
  await db.query("DELETE FROM push_subscriptions WHERE endpoint = $1 AND user_id = $2", [endpoint, req.user.id]);
  res.json({ message: "Abonelik kaldırıldı." });
});

/**
 * MOBİL — Cihaz push token'ı kaydet (FCM). body: { token, platform: "android"|"ios"|"web", app_version? }
 * Aynı token başka bir kullanıcıya aitse (aynı telefonda hesap değişimi) bu kullanıcıya devredilir.
 * Şimdilik yalnız kayıt tutulur; gönderim services/fcm.js içinde bağlanacak.
 */
router.post("/device", requireAuth, async (req, res) => {
  const { token, platform, app_version } = req.body;
  if (typeof token !== "string" || token.length < 10 || token.length > 4096) {
    return res.status(400).json({ error: "Geçerli bir cihaz token'ı (token) zorunludur." });
  }
  if (!["android", "ios", "web"].includes(platform)) {
    return res.status(400).json({ error: "platform android, ios veya web olmalıdır." });
  }
  const { rows } = await db.query(
    `INSERT INTO device_tokens (user_id, token, platform, app_version)
     VALUES ($1,$2,$3,$4)
     ON CONFLICT (token) DO UPDATE SET user_id = $1, platform = $3, app_version = $4, updated_at = now()
     RETURNING id, platform, app_version, created_at, updated_at`,
    [req.user.id, token, platform, app_version ? String(app_version).slice(0, 40) : null]
  );
  res.status(201).json(rows[0]);
});

/** MOBİL — Cihaz token'ını sil (çıkış yaparken). Token gövdede ({token}) ya da ?token= ile verilir; yalnız kendi token'ı silinir. */
router.delete("/device", requireAuth, async (req, res) => {
  const token = (req.body && req.body.token) || req.query.token;
  if (typeof token !== "string" || !token) return res.status(400).json({ error: "token gerekli." });
  const r = await db.query("DELETE FROM device_tokens WHERE token = $1 AND user_id = $2", [token, req.user.id]);
  res.json({ message: "Cihaz kaydı kaldırıldı.", removed: r.rowCount });
});

module.exports = router;
