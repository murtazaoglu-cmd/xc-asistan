const db = require("../../db");
const clock = require("../clock");
module.exports.register = (registerHandler) => {
  // Günlük temizlik: eski idempotency kayıtları (48 sa), bitmiş işler (30 gün), eski kalp atışları (7 gün), okunmuş eski bildirimler (180 gün)
  registerHandler("housekeeping", async () => {
    const now = clock.now();
    const d = (ms) => new Date(now.getTime() - ms);
    const DAY = 86400000;
    await db.query("DELETE FROM idempotency_keys WHERE created_at < $1", [d(2 * DAY)]);
    await db.query("DELETE FROM jobs WHERE status IN ('done','skipped','failed') AND finished_at < $1", [d(30 * DAY)]);
    await db.query("DELETE FROM worker_heartbeats WHERE last_tick_at < $1", [d(7 * DAY)]);
    await db.query("DELETE FROM notification_outbox WHERE created_at < $1 AND (read_at IS NOT NULL OR status IN ('iptal','basarisiz'))", [d(180 * DAY)]);
    // v19: yazışma/öneri/komut ham metni saklama ve imha (KVKK); hata diğer temizlikleri bozmasın
    try { await require("../importer/retention").purge(now); } catch (e) { console.error("[housekeeping] retention.purge hatası:", e.message); }
  });
};
