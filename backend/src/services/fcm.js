/**
 * Mobil (FCM) push kancası. v17'den itibaren çağıranlar (push.js: notifyNewOffer / notifyUser) bildirimi
 * notification_outbox'a yazar (assistant/notify); gönderimi worker'daki sender.js yapar (FCM yapılandırılmışsa)
 * ve uygulama içi bildirim kutusundan (GET /api/assistant/inbox) okunur. Çağıranlar değişmedi.
 *
 * message: { title, body, url?, data? }   data.type + data.id varsa aynı olay aynı kullanıcıya tek bildirim üretir (dedupeKey).
 * Dönüş: { sent: 0, queued: n } — sent hep 0 (gönderim worker'da, asenkron).
 */
async function sendToUsers(userIds, message) {
  const { notifyUser } = require("../assistant/notify");
  const data = (message && message.data) || {};
  let queued = 0;
  for (const uid of userIds || []) {
    try {
      const r = await notifyUser(uid, {
        type: data.type || "genel", title: message.title, body: message.body || "", data,
        dedupeKey: data.type && data.id ? `${data.type}:${data.id}:${uid}` : undefined,
      });
      if (!r.deduped) queued++;
    } catch (err) { console.error("FCM kancası (outbox) hatası:", err.message); }
  }
  return { sent: 0, queued };
}

module.exports = { sendToUsers };
